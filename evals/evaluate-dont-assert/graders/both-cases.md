# Were both forms actually evaluated?

The prompt asks two things: with a delimiter and without one. PASS only if both
were evaluated and both values reported. Answering one and inferring the other
is a FAIL — inferring is the behaviour under test.
