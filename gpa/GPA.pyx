import numpy
from libc.math cimport pow, fabs, sqrt, atan2, M_PI, sin, cos,tan
from math import radians
from scipy.spatial import Delaunay as Delanuay

from cpython cimport bool
cimport numpy
cimport cython

@cython.boundscheck(False)
@cython.wraparound(False)
@cython.nonecheck(False)
@cython.cdivision(True)
cdef class GPA:
    cdef public float[:,:] mat,gradient_dx,gradient_dy,gradient_asymmetric_dy,gradient_asymmetric_dx
    cdef public float cx, cy, r
    cdef int rows, cols
    
    cdef float[:,:] phases, mods
    cdef int[:,:] removedP, nremovedP
    cdef public object triangulation_points,triangles
    cdef public int totalAssimetric, totalVet
    cdef public float phaseDiversity, maxGrad

    cdef public int n_edges, n_points
    cdef public float G1, G2

    #@profile
    def __cinit__(self, mat):
        # setting matrix,and calculating the gradient field
        self.mat = mat

        # default value
        self.setPosition(float(len(mat))/2.0,float(len(mat[0]))/2.0)
        self.r = max(float(len(mat))/2.0,float(len(mat[0]))/2.0)
   
        # percentual Ga proprieties
        self.cols = len(self.mat[0])
        self.rows = len(self.mat)
        self.totalVet = self.rows * self.cols
        self.totalAssimetric = self.rows * self.cols
        self.removedP = numpy.array([[]],dtype=numpy.int32)
        self.nremovedP = numpy.array([[]],dtype=numpy.int32)
        self.triangulation_points = []
        self.phaseDiversity = 0.0

    @cython.boundscheck(False)
    @cython.wraparound(False)
    @cython.nonecheck(False)
    @cython.cdivision(True)
    cpdef void setPosition(self, float cx, float cy):
        self.cx = cx
        self.cy = cy

    @cython.boundscheck(False)
    @cython.wraparound(False)
    @cython.nonecheck(False)
    @cython.cdivision(True)
    cdef void _setGradients(self):
        cdef int w, h,i,j
        cdef float[:,:] gx, gy
        gy, gx = self.gradient(self.mat)
        w, h = len(gx[0]),len(gx)
        
       
        self.maxGrad = -1.0
        for i in range(w):
            for j in range(h):
                if(self.maxGrad<0.0) or (sqrt(pow(gy[j, i],2.0)+pow(gx[j, i],2.0))>self.maxGrad):
                    self.maxGrad = sqrt(pow(gy[j, i],2.0)+pow(gx[j, i],2.0))
        
        #initialization
        self.gradient_dx=numpy.array([[gx[j, i] for i in range(w) ] for j in range(h)],dtype=numpy.float32)
        self.gradient_dy=numpy.array([[gy[j, i] for i in range(w) ] for j in range(h)],dtype=numpy.float32)

        # copying gradient field to asymmetric gradient field
        self.gradient_asymmetric_dx = numpy.array([[gx[j, i] for i in range(w) ] for j in range(h)],dtype=numpy.float32)
        self.gradient_asymmetric_dy = numpy.array([[gy[j, i] for i in range(w) ] for j in range(h)],dtype=numpy.float32)

        # calculating the phase and mod of each vector
        self.phases = numpy.array([[atan2(gy[j, i],gx[j, i])
                                     for i in range(w) ] for j in range(h)],dtype=numpy.float32)
        self.mods = numpy.array([[sqrt(pow(gy[j, i],2.0)+pow(gx[j, i],2.0)) for i in range(w) ] for j in range(h)],dtype=numpy.float32)
   
    @cython.boundscheck(False)
    @cython.wraparound(False)
    @cython.nonecheck(False)
    @cython.cdivision(True)
    cdef float _min(self,float a, float b):
        if a < b:
            return a
        else:
            return b

    @cython.boundscheck(False)
    @cython.wraparound(False)
    @cython.nonecheck(False)
    @cython.cdivision(True)
    cdef float _angleDifference(self, float a1,float a2):
        return self._min(fabs(a1-a2), fabs(fabs(a1-a2)-2.0*M_PI))

    @cython.boundscheck(False)
    @cython.wraparound(False)
    @cython.nonecheck(False)
    @cython.cdivision(True)
    cdef void _update_asymmetric_mat(self,float[:] index_dist,float[:,:] dists,float mtol,float ftol,float ptol):
        cdef int ind, lx, px, py, px2, py2, i, j
        cdef int[:] x, y

        # distances loop
        for ind in range(0, len(index_dist)):
            x2, y2 =[], []
            for py in range(self.rows):
                for px in range(self.cols):
                    if (fabs(dists[py, px]-index_dist[ind]) <= fabs(ptol)):
                        x2.append(px)
                        y2.append(py)
            x, y =numpy.array(x2,dtype=numpy.int32), numpy.array(y2,dtype=numpy.int32)
            lx = len(x)

            # compare each point in the same distance
            for i in range(lx):
                px, py = x[i], y[i]
                if (self.mods[py, px]/self.maxGrad <= mtol):
                    self.gradient_asymmetric_dx[py, px] = 0.0
                    self.gradient_asymmetric_dy[py, px] = 0.0
                for j in range(lx):
                    px2, py2 = x[j], y[j]
                    if (fabs(self.mods[py, px]- self.mods[py2, px2] )<= mtol*self.maxGrad):
                        if (fabs(self._angleDifference(self.phases[py, px], self.phases[py2, px2])-M_PI)  <= ftol):
                            self.gradient_asymmetric_dx[py, px] = 0.0
                            self.gradient_asymmetric_dy[py, px] = 0.0
                            self.gradient_asymmetric_dx[py2, px2] = 0.0
                            self.gradient_asymmetric_dy[py2, px2] = 0.0
                            break

        #Remove boundaries that may cause some trouble
        #for py in range(self.rows):
        #    self.gradient_asymmetric_dx[py, 0] = 0.0
        #    self.gradient_asymmetric_dy[py, self.cols-1] = 0.0
        #for px in range(self.cols):
        #    self.gradient_asymmetric_dx[0, px] = 0.0
        #    self.gradient_asymmetric_dy[self.rows-1, px] = 0.0

        self.totalVet = 0
        self.totalAssimetric = 0
        nremovedP = []
        removedP = []
        for j in range(self.rows):
            for i in range(self.cols):
                if (self.gradient_asymmetric_dy[j,i] == 0.0) and (self.gradient_asymmetric_dx[j,i] == 0.0):
                    removedP.append([j,i])
                    self.totalVet = self.totalVet+1
                else:
                    nremovedP.append([j,i])
                    self.totalVet = self.totalVet+1
                    self.totalAssimetric = self.totalAssimetric+1
        if(len(nremovedP)>0):
            self.nremovedP = numpy.array(nremovedP,dtype=numpy.int32)
        if(len(removedP)>0):
            self.removedP = numpy.array(removedP,dtype=numpy.int32)

    @cython.boundscheck(False)
    @cython.wraparound(False)
    @cython.nonecheck(False)
    @cython.cdivision(True)
    cdef float _vectorialVariety(self):
        cdef int i
        cdef float somax,somay, phase, alinhamento, mod, smod
        somax = 0.0
        somay = 0.0
        smod = 0.0
        if(self.totalAssimetric<1):
            return 0.0
        for i in range(self.totalAssimetric):
            phase = self.phases[self.nremovedP[i,0],self.nremovedP[i,1]]
            mod = self.mods[self.nremovedP[i,0],self.nremovedP[i,1]]
            somax += self.gradient_dx[self.nremovedP[i,0],self.nremovedP[i,1]]
            somay += self.gradient_dy[self.nremovedP[i,0],self.nremovedP[i,1]]
            smod += mod
        if smod <= 0.0:
            return 0.0
        alinhamento = sqrt(pow(somax,2.0)+pow(somay,2.0))/smod
        return alinhamento


    @cython.boundscheck(False)
    @cython.wraparound(False)
    @cython.nonecheck(False)
    @cython.cdivision(True)
    cdef float _modDiversity(self):
        #unused variety equation
        cdef int i, j
        cdef float total, modDiversity
        total = float(self.totalAssimetric*(self.totalAssimetric-1))/2.0
        modDiversity = 0.0
        if(self.totalAssimetric<2):
            return 0.0
        maxMod = 0.0
        for i in range(self.totalAssimetric):
            if fabs(self.mods[self.nremovedP[i,0],self.nremovedP[i,1]]) > maxMod:
                maxMod = fabs(self.mods[self.nremovedP[i,0],self.nremovedP[i,1]])
        for i in range(self.totalAssimetric):
            for j in range(i+1,self.totalAssimetric): 
                modDiversity += fabs(self.mods[self.nremovedP[i,0],self.nremovedP[i,1]]/maxMod-self.mods[self.nremovedP[j,0],self.nremovedP[j,1]]/maxMod)/total
        return modDiversity

    @cython.boundscheck(False)
    @cython.wraparound(False)
    @cython.nonecheck(False)
    @cython.cdivision(True)
    cdef void _G2(self):
        if(len(self.nremovedP[0])>0):
            self.totalAssimetric = len(self.nremovedP[:,0])
        else:
            self.totalAssimetric = 0
        self.phaseDiversity = self._vectorialVariety()
        self.G2 = round((self.totalAssimetric)/float(self.totalVet)*(2.0-self.phaseDiversity),5)
        

    @cython.boundscheck(False)
    @cython.wraparound(False)
    @cython.nonecheck(False)
    @cython.cdivision(True)
    # This function estimates both asymmetric gradient coeficient (geometric and algebric), with the given tolerances
    cpdef list evaluate(self,float mtol, float ftol,float ptol,list moment=["G2"]):
        self._setGradients()
        cdef int[:] i
        cdef int x, y
        cdef float minimo, maximo

        self.cols = len(self.mat[0])
        self.rows = len(self.mat)

        cdef numpy.ndarray dists = numpy.array([[sqrt(pow(float(x)-self.cx, 2.0)+pow(float(y)-self.cy, 2.0)) \
                                                  for x in range(self.cols)] for y in range(self.rows)])
        minimo, maximo = numpy.min(dists),numpy.max(dists)
        sequence = numpy.arange(minimo,maximo,ptol/2.0).astype(dtype=numpy.float32)
        cdef numpy.ndarray uniq = numpy.array([minimo for minimo in  sequence])
        
        # removes the symmetry in gradient_asymmetric_dx and gradient_asymmetric_dy:
        self._update_asymmetric_mat(uniq.astype(dtype=numpy.float32), dists.astype(dtype=numpy.float32), mtol, ftol, ptol)
       
        #gradient moments:
        retorno = []
        if("G2" in moment):
            self._G2()
            retorno.append(self.G2)
        if("G1" in moment):
            self._G1(mtol)
            retorno.append(self.G1)
        return retorno

    @cython.boundscheck(False)
    @cython.wraparound(False)
    @cython.nonecheck(False)
    @cython.cdivision(True)
    cdef bool _wasRemoved(self, int j,int i):
        cdef int rp
        for rp in range(self.totalVet - self.totalAssimetric):
            if(self.removedP[rp,0] == j) and(self.removedP[rp,1] == i):
                return True
        return False 
   
    @cython.boundscheck(False)
    @cython.wraparound(False)
    @cython.nonecheck(False)
    @cython.cdivision(True)
    cdef tuple gradient(self,float[:,:] mat):
        cdef float[:,:] dx, dy
        cdef int i, j,w,h
        w, h = len(mat[0]),len(mat)
        dx = numpy.array([[0.0 for i in range(w) ] for j in range(h)],dtype=numpy.float32)
        dy = numpy.array([[0.0 for i in range(w) ] for j in range(h)],dtype=numpy.float32)
        for i in range(w):
           for j in range(h):
              #y gradient:
              if(j+1<h) and (j-1>-1):
                 dy[j, i] = (mat[j+1, i] - mat[j-1, i])/2.0
              elif(j+1<h):
                 dy[j, i] = (mat[j+1, i] - mat[j, i])/1.0
              elif(j-1>-1):
                 dy[j, i] = (mat[j, i] - mat[j-1, i])/1.0
              #x gradient:
              if(i+1<w) and (i-1>-1):
                 dx[j, i] = (mat[j, i+1] - mat[j, i-1])/2.0
              elif(i+1<w):
                 dx[j, i] = (mat[j, i+1] - mat[j, i])/1.0
              elif(i-1>-1):
                 dx[j, i] = (mat[j, i] - mat[j, i-1])/1.0
        return dy,dx

    @cython.boundscheck(False)
    @cython.wraparound(False)
    @cython.nonecheck(False)
    @cython.cdivision(True)
    def _G1(self,float tol):
        cdef int w, h, i, j
        cdef float mod

        for i in range(self.rows):
            for j in range(self.cols):
                mod = (self.gradient_asymmetric_dx[i, j]**2+self.gradient_asymmetric_dy[i, j]**2)**0.5
                if mod > tol:
                    self.triangulation_points.append([j+0.5*self.gradient_asymmetric_dx[i, j], i+0.5*self.gradient_asymmetric_dy[i, j]])
        self.triangulation_points = numpy.array(self.triangulation_points)
        self.n_points = len(self.triangulation_points)
        if self.n_points < 3:
            self.n_edges = 0
            self.G1 = 0
        else:
            self.triangles = Delanuay(self.triangulation_points)
            neigh = self.triangles.vertex_neighbor_vertices
            self.n_edges = len(neigh[1])/2
            self.G1 = float(self.n_edges-self.n_points)/float(self.n_points)
        return self.G1

                 
                 
 
               


