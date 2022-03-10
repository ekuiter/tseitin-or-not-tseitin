import sys
import z3

s = z3.Solver()
g = z3.Goal()
with open(sys.argv[1], 'rb') as fp:
  g.add(z3.parse_smt2_string(fp.read()))
s.add(g)
print(s.dimacs())