import sys
import z3

# The following is NOT the correct code to Tseitin-transform a Boolean formula into CNF:
# s = z3.Solver()
# g = z3.Goal()
# with open(sys.argv[1], 'rb') as fp:
#   g.add(z3.parse_smt2_string(fp.read()))
# s.add(g)
# print(s.dimacs())
# This is wrong because .dimacs() does not call the tseitin-cnf tactic. Even
# s = z3.Tactic("tseitin-cnf").solver()
# does not work, as the actual solver is not called by .dimacs().
# Instead, this performs some kind of slicing/variable elimination, so
# model counting and core/dead features cannot be reliably calculated.
# For a correct Tseitin transformation, use the following:

goal = z3.Goal()
with open(sys.argv[1], 'rb') as file:
  goal.add(z3.parse_smt2_string(file.read()))
goal = z3.Tactic("tseitin-cnf")(goal)[0]
print(goal.dimacs())