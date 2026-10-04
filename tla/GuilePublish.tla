---------------------------- MODULE GuilePublish ----------------------------
(***************************************************************************)
(* The release labels and the publish pipeline of this plugin, as a state   *)
(* machine transcribed from .github/workflows/{gate,publish}.yml and        *)
(* scripts/release.sh. The question it answers is the one a person asks of  *)
(* a PR: CAN I SEE FROM ITS LABELS WHETHER IT PASSED, AND WHETHER IT SHIPPED? *)
(*                                                                         *)
(* Conventions follow aygp-dr/standard-change/tla: one boolean CONSTANT per *)
(* rule, so the model can fail once per rule, and check.sh runs every rule  *)
(* both ways. A model that can only pass verifies nothing.                  *)
(*                                                                         *)
(* Two phases, joined by the merge:                                        *)
(*                                                                         *)
(*   GATE (pre-merge, gate.yml): one run per push, runs can overlap (no     *)
(*   concurrency group). Labels release:start, release:end, and -- proposed *)
(*   -- release:failed.                                                    *)
(*                                                                         *)
(*   PUBLISH (post-merge, publish.yml + release.sh): one run per merged     *)
(*   deployable PR, plus a manual dispatch. A publish is two artifacts, the *)
(*   tag and the release, and a run can fail between them. Proposed: an     *)
(*   outcome label on the PR, published or publish:failed.                  *)
(***************************************************************************)
EXTENDS Naturals, FiniteSets

CONSTANTS
    MaxPush,          \* pushes after opening, per PR
    MaxFault,         \* bound on injected faults (gate failure, crash, silent no-op)
    FoldedRelease,    \* SCENARIO: merging "rel" also marks "sub" merged (the 0.4.0 shape)
    \* ---- gate.yml rules ----
    StartClearsEnd,   \* a gate run removes release:end when it adds release:start    (NOT deployed)
    CurrentHeadOnly,  \* a gate run labels only if its commit is still the PR's head (NOT deployed)
    GateFailLabel,    \* a failed gate adds release:failed; a pass removes it          (NOT deployed)
    \* ---- publish.yml / release.sh rules ----
    Concurrency,      \* publish runs are serialised by a concurrency group            (deployed, #28)
    IdempotentDone,   \* a run that finds tag+release already at HEAD ends green     (deployed, #28)
    ResumeOnRelease,  \* the state includes the release, so tag-without-release resumes (deployed, #28)
    PostVerify,       \* after publishing, re-read the state; not done => red          (deployed, #28)
    OutcomeLabel      \* a finished publish labels its PR published / publish:failed    (NOT deployed)

PRs   == {"rel", "sub"}
Runs  == PRs \cup {"dispatch"}
Heads == 0..MaxPush
Terminal == {"green", "skip", "red"}

VARIABLES
    head,      \* head[p]: the PR's current commit
    pend,      \* pend[p]: gate runs queued, by the commit they test
    running,   \* running[p]: gate runs that have labelled release:start
    ran,       \* ran[p]: commits a gate run has finished on (either way)
    passed,    \* passed[p]: commits the gate passed on
    glabels,   \* glabels[p] \subseteq {"start","end","failed"}: what the PR shows
    merged,    \* merged[p]: the forge records MERGED
    pc,        \* pc[r]: where publish run r is
    resume,    \* resume[r]: run r's check found the tag at HEAD without a release
    lock,      \* the concurrency group's holder, or "free"
    tag,       \* "none" | "head": the version tag, and where it points
    rel,       \* the GitHub release for that tag exists
    outcome,   \* "none"|"published"|"failed": the publish label on the RELEASE PR ("rel"),
               \* the one whose merge commit carries the version. Every run -- sub's and a
               \* dispatch's included -- labels that PR; the last to finish wins.
    faults,    \* injected faults so far
    badRace,   \* history: a run tried to create a tag another run had just created
    badRed     \* history: a run went red for a version that was already fully published

vars == <<head, pend, running, ran, passed, glabels, merged,
          pc, resume, lock, tag, rel, outcome, faults, badRace, badRed>>

TypeOK ==
    /\ head \in [PRs -> Heads]
    /\ pend \in [PRs -> SUBSET Heads]
    /\ running \in [PRs -> SUBSET Heads]
    /\ ran \in [PRs -> SUBSET Heads]
    /\ passed \in [PRs -> SUBSET Heads]
    /\ glabels \in [PRs -> SUBSET {"start", "end", "failed"}]
    /\ merged \in [PRs -> BOOLEAN]
    /\ pc \in [Runs -> {"idle", "queued", "check", "gate", "publish", "tagged", "verify"} \cup Terminal]
    /\ resume \in [Runs -> BOOLEAN]
    /\ lock \in Runs \cup {"free"}
    /\ tag \in {"none", "head"}
    /\ rel \in BOOLEAN
    /\ outcome \in {"none", "published", "failed"}
    /\ faults \in 0..MaxFault

Init ==
    /\ head = [p \in PRs |-> 0]
    /\ pend = [p \in PRs |-> {0}]          \* opening a PR triggers the gate
    /\ running = [p \in PRs |-> {}]
    /\ ran = [p \in PRs |-> {}]
    /\ passed = [p \in PRs |-> {}]
    /\ glabels = [p \in PRs |-> {}]
    /\ merged = [p \in PRs |-> FALSE]
    /\ pc = [r \in Runs |-> "idle"]
    /\ resume = [r \in Runs |-> FALSE]
    /\ lock = "free"
    /\ tag = "none"
    /\ rel = FALSE
    /\ outcome = "none"
    /\ faults = 0
    /\ badRace = FALSE
    /\ badRed = FALSE

PublishVars == <<pc, resume, lock, tag, rel, outcome, badRace, badRed>>
GateVars    == <<head, pend, running, ran, passed, glabels, merged>>

(***************************************************************************)
(*                               GATE (gate.yml)                            *)
(***************************************************************************)

\* synchronize: a new commit, and a new gate run for it. The old run keeps going.
Push(p) ==
    /\ ~merged[p] /\ head[p] < MaxPush
    /\ head' = [head EXCEPT ![p] = @ + 1]
    /\ pend' = [pend EXCEPT ![p] = @ \cup {head[p] + 1}]
    /\ UNCHANGED <<running, ran, passed, glabels, merged, faults>>
    /\ UNCHANGED PublishVars

\* A run may label only while its commit is the head -- if CurrentHeadOnly.
MayLabel(p, h) == ~CurrentHeadOnly \/ h = head[p]

\* gate.yml "Mark release:start". Deployed: adds start, leaves any old end in place.
GateBegin(p, h) ==
    /\ h \in pend[p]
    /\ pend' = [pend EXCEPT ![p] = @ \ {h}]
    /\ running' = [running EXCEPT ![p] = @ \cup {h}]
    /\ glabels' = [glabels EXCEPT ![p] =
                     IF MayLabel(p, h)
                     THEN (IF StartClearsEnd THEN @ \ {"end", "failed"} ELSE @) \cup {"start"}
                     ELSE @]
    /\ UNCHANGED <<head, ran, passed, merged, faults>>
    /\ UNCHANGED PublishVars

\* gate.yml "Mark release:end".
GatePass(p, h) ==
    /\ h \in running[p]
    /\ running' = [running EXCEPT ![p] = @ \ {h}]
    /\ ran' = [ran EXCEPT ![p] = @ \cup {h}]
    /\ passed' = [passed EXCEPT ![p] = @ \cup {h}]
    /\ glabels' = [glabels EXCEPT ![p] =
                     IF MayLabel(p, h) THEN (@ \ {"start", "failed"}) \cup {"end"} ELSE @]
    /\ UNCHANGED <<head, pend, merged, faults>>
    /\ UNCHANGED PublishVars

\* gate.yml "Clear release:start on failure". Deployed: removes start, adds nothing.
GateFail(p, h) ==
    /\ h \in running[p] /\ faults < MaxFault
    /\ running' = [running EXCEPT ![p] = @ \ {h}]
    /\ ran' = [ran EXCEPT ![p] = @ \cup {h}]
    /\ glabels' = [glabels EXCEPT ![p] =
                     IF MayLabel(p, h)
                     THEN (@ \ {"start"}) \cup (IF GateFailLabel THEN {"failed"} ELSE {})
                     ELSE @]
    /\ faults' = faults + 1
    /\ UNCHANGED <<head, pend, passed, merged>>
    /\ UNCHANGED PublishVars

(***************************************************************************)
(*                   MERGE, and what it triggers (publish.yml `on:`)        *)
(***************************************************************************)

\* Merging "rel". Branch protection is NOT assumed: publish re-runs the gate.
\* With FoldedRelease, "sub" is marked merged too, and fires its own `closed'.
Merge ==
    /\ ~merged["rel"]
    /\ merged' = [p \in PRs |-> IF p = "rel" \/ (FoldedRelease /\ p = "sub") THEN TRUE ELSE merged[p]]
    /\ pc' = [r \in Runs |-> IF r = "rel" \/ (FoldedRelease /\ r = "sub") THEN "queued" ELSE pc[r]]
    /\ UNCHANGED <<head, pend, running, ran, passed, glabels, faults>>
    /\ UNCHANGED <<resume, lock, tag, rel, outcome, badRace, badRed>>

\* workflow_dispatch: a person re-runs publish, at most once, after the merge.
Dispatch ==
    /\ merged["rel"] /\ pc["dispatch"] = "idle"
    /\ pc' = [pc EXCEPT !["dispatch"] = "queued"]
    /\ UNCHANGED GateVars
    /\ UNCHANGED <<resume, lock, tag, rel, outcome, faults, badRace, badRed>>

(***************************************************************************)
(*                    PUBLISH (publish.yml + scripts/release.sh)            *)
(***************************************************************************)

Finish(r, o) ==
    /\ pc' = [pc EXCEPT ![r] = o]
    /\ lock' = IF lock = r THEN "free" ELSE lock
    /\ outcome' = IF OutcomeLabel THEN (IF o = "red" THEN "failed" ELSE "published")
                  ELSE outcome

Start(r) ==
    /\ pc[r] = "queued"
    /\ Concurrency => lock = "free"
    /\ pc' = [pc EXCEPT ![r] = "check"]
    /\ lock' = IF Concurrency THEN r ELSE lock
    /\ UNCHANGED GateVars
    /\ UNCHANGED <<resume, tag, rel, outcome, faults, badRace, badRed>>

Done == tag = "head" /\ rel

\* release.sh status: none | done | resume (conflict needs a second commit; not modelled).
Check(r) ==
    /\ pc[r] = "check"
    /\ IF tag = "head" /\ IdempotentDone /\ (Done \/ ~ResumeOnRelease)
          THEN \* done, or -- without ResumeOnRelease -- "tag at HEAD" alone taken as done
               /\ Finish(r, "skip") /\ UNCHANGED <<resume, badRed>>
       ELSE IF tag = "head" /\ ~(ResumeOnRelease /\ ~Done)
          THEN \* the old publish.yml: an existing tag is an error, even a finished one
               /\ Finish(r, "red")
               /\ badRed' = (badRed \/ Done)
               /\ UNCHANGED resume
       ELSE /\ pc' = [pc EXCEPT ![r] = "gate"]
            /\ resume' = [resume EXCEPT ![r] = (tag = "head")]
            /\ UNCHANGED <<lock, outcome, badRed>>
    /\ UNCHANGED GateVars
    /\ UNCHANGED <<tag, rel, faults, badRace>>

\* release.sh gate(): `make checks' and `gh skill publish --dry-run'.
PubGate(r) ==
    /\ pc[r] = "gate"
    /\ \/ /\ pc' = [pc EXCEPT ![r] = "publish"]
          /\ UNCHANGED <<lock, outcome, faults>>
       \/ /\ faults < MaxFault /\ faults' = faults + 1
          /\ Finish(r, "red")
    /\ UNCHANGED GateVars
    /\ UNCHANGED <<resume, tag, rel, badRace, badRed>>

\* gh skill publish --tag (creates the tag), or, resuming, the tag already exists.
Publish(r) ==
    /\ pc[r] = "publish"
    /\ IF resume[r]
          THEN /\ pc' = [pc EXCEPT ![r] = "tagged"] /\ UNCHANGED <<lock, outcome, tag, badRace>>
       ELSE IF tag = "none"
          THEN /\ tag' = "head" /\ pc' = [pc EXCEPT ![r] = "tagged"]
               /\ UNCHANGED <<lock, outcome, badRace>>
       ELSE \* it checked "none", and another run has tagged since: the immutable tag refuses
            /\ badRace' = TRUE /\ Finish(r, "red") /\ UNCHANGED tag
    /\ UNCHANGED GateVars
    /\ UNCHANGED <<resume, rel, faults, badRed>>

\* The release: created, or the run dies first, or the command claims success and does nothing.
MakeRelease(r) ==
    /\ pc[r] = "tagged"
    /\ \/ /\ rel' = TRUE /\ pc' = [pc EXCEPT ![r] = "verify"]
          /\ UNCHANGED <<lock, outcome, faults>>
       \/ /\ faults < MaxFault /\ faults' = faults + 1        \* crash between tag and release
          /\ Finish(r, "red") /\ UNCHANGED rel
       \/ /\ faults < MaxFault /\ faults' = faults + 1        \* silent no-op, reported as success
          /\ pc' = [pc EXCEPT ![r] = "verify"] /\ UNCHANGED <<rel, lock, outcome>>
    /\ UNCHANGED GateVars
    /\ UNCHANGED <<resume, tag, badRace, badRed>>

Verify(r) ==
    /\ pc[r] = "verify"
    /\ Finish(r, IF PostVerify /\ ~Done THEN "red" ELSE "green")
    /\ UNCHANGED GateVars
    /\ UNCHANGED <<resume, tag, rel, faults, badRace, badRed>>

Next ==
    \/ \E p \in PRs : Push(p)
    \/ \E p \in PRs, h \in Heads : GateBegin(p, h) \/ GatePass(p, h) \/ GateFail(p, h)
    \/ Merge \/ Dispatch
    \/ \E r \in Runs : Start(r) \/ Check(r) \/ PubGate(r) \/ Publish(r) \/ MakeRelease(r) \/ Verify(r)

Spec == Init /\ [][Next]_vars

(***************************************************************************)
(*                               INVARIANTS                                 *)
(* Each is named in check.sh next to the rule whose absence breaks it.      *)
(***************************************************************************)

GateQuiet(p) == pend[p] = {} /\ running[p] = {}

\* What a reviewer reads as "the gate passed on this PR" is true of its HEAD.
\* Broken by StartClearsEnd=FALSE (a stale end survives a failed re-run) and by
\* CurrentHeadOnly=FALSE (an older run finishing last labels a newer head).
EndMeansHeadPassed ==
    \A p \in PRs : (GateQuiet(p) /\ "end" \in glabels[p]) => head[p] \in passed[p]

\* A failed gate on the head is visible, not indistinguishable from "never ran".
GateFailureVisible ==
    \A p \in PRs : (GateQuiet(p) /\ head[p] \in ran[p] /\ head[p] \notin passed[p])
                   => "failed" \in glabels[p]

\* Green means shipped.
NoFalseGreen == \A r \in Runs : pc[r] \in {"green", "skip"} => Done

\* Two runs never race for the one immutable tag.
NoTagRace == badRace = FALSE

\* A version already published never turns a later run red.
NoRedOnPublished == badRed = FALSE

PublishQuiet == merged["rel"] /\ \A r \in Runs : pc[r] \in Terminal \cup {"idle"}

\* When publishing has settled, the merged PR's labels say which way it went.
PublishOutcomeVisible ==
    PublishQuiet => outcome = (IF Done THEN "published" ELSE "failed")

\* A settled gate never leaves release:start behind (a run that labels its begin
\* but not its end -- e.g. a stale run skipping only the end -- would).
NoStuckStart == \A p \in PRs : GateQuiet(p) => "start" \notin glabels[p]
=============================================================================
