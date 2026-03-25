"""
ATRSC Project - Warehouse optimization 
"""

# Builtin simulator import
import Pkg
Pkg.add(Pkg.PackageSpec(name="ResumableFunctions", version="0.6"))
Pkg.add(Pkg.PackageSpec(name="SimJulia", version="0.6"))
using SimJulia
using ResumableFunctions


#### DATA STRUCTURES ####

struct Product 
    id::Int 
    arrival_rate::Float64
    processing_time::Dict{Int,Tuple{Float64, Float64}}
    route::Vector{Int} 
end 

struct Machine 
    id::Int
    resource::Resource
end 

struct Worker 
    instance::Int 
    id::Int 
    qualifications::Vector{Int}
end 

#### INSTANCES ####

T1 = Product(
    1, 
    0.29, 
    Dict(
        1 => (0.58, 0.78),
        2 => (0.23, 0.56),
        3 => (0.81, 0.93),
        4 => (0.12, 0.39),
        8 => (0.82, 1.04)
        ),
    [1, 2, 3, 4, 8]) # order of machines by indices 

T2 = Product(
    2, 
    0.32, 
    Dict(
        2 => (0.59, 0.68),
        4 => (0.74, 0.77),
        7 => (0.3, 0.55)
        ),
    [2, 4, 7])

T3 = Product(
    3, 
    0.47, 
    Dict(
        1 => (0.57, 0.64),
        3 => (0.37, 0.54),
        5 => (0.35, 0.63)
        ),
    [3, 5, 1])

T4 = Product(
    4, 
    0.38, 
    Dict(
        5 => (0.36, 0.51),
        6 => (0.61, 0.7),
        7 => (0.78, 0.85),
        8 => (0.18, 0.37)
        ),
    [5, 6, 7, 8])

M1 = Machine(1, Resource(env, capacity=1))
M2 = Machine(2, Resource(env, capacity=1))
M3 = Machine(3, Resource(env, capacity=1))
M4 = Machine(4, Resource(env, capacity=1))
M5 = Machine(5, Resource(env, capacity=1))
M6 = Machine(6, Resource(env, capacity=1))
M7 = Machine(7, Resource(env, capacity=1))
M8 = Machine(8, Resource(env, capacity=1))

# Instance 1 workers 
E1 = Worker(1, [1,2])
E2 = Worker(2, [1,2])
E3 = Worker(3, [1,2])
E4 = Worker(4, [1,2])

### Poisson Arrivals of Products ###



env = simulation()

run(env)