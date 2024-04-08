# XIRR-in-Postgresql
Computing XIRR in postgresql stored procedure

This is a work in progress project. 

There are two pupular approaches to solving the XIRR equation which is

f(x) = FOR EACH n = 0 to n SUM(Pn / (1 + Rn) ^ delta_t)

XIRR_NR_method.sql has an implementation of Newton-Raphson Method

XIRR_bisection_method.sql has an implementation of Bisection method

Both are implemented and tested on Postgresql db. 

They need improvements in error handling and boundary condition management.
