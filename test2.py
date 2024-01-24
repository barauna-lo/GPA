from GPA import GPA
import numpy as np

z = np.zeros((16,16))
ga = GPA(0.0)
print(ga(z,moment=['G1','G2','G3','G4']))
