import pickle
import sys
import z3

def get_kclause_constraints(kclause_file):
  with open(kclause_file, 'rb') as fp:
    kclause = pickle.load(fp)

    kclause_constraints = {}
    for var in kclause.keys():
      kclause_constraints[var] = [ z3.parse_smt2_string(clause) for clause in kclause[var] ]

    constraints = []
    for var in kclause_constraints.keys():
      for z3_clause in kclause_constraints[var]:
        constraints.extend(z3_clause)

    return constraints

constraints = get_kclause_constraints(sys.argv[1])
solver = z3.Solver()
g = z3.Goal()
g.add(constraints)
t = z3.Tactic('tseitin-cnf') # todo: comment this out and compare results
solver.add(g)
print(solver.dimacs())
