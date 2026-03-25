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

struct ProductType
    id::Int
    arrival_rate::Float64
    processing_time::Dict{Int,Tuple{Float64, Float64}}
    route::Vector{Int}
end

struct Job 
    id::Int
    product::ProductType
    arrival::Float64
    step::Int # where we are in the route
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

struct System 
    machine_queues::Dict{int, Vector}
    available_workers::Vector{Worker}
    last_job_id::Int
end 

#### INSTANCES ####

T1 = ProductType(
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

T2 = ProductType(
    2, 
    0.32, 
    Dict(
        2 => (0.59, 0.68),
        4 => (0.74, 0.77),
        7 => (0.3, 0.55)
        ),
    [2, 4, 7])

T3 = ProductType(
    3, 
    0.47, 
    Dict(
        1 => (0.57, 0.64),
        3 => (0.37, 0.54),
        5 => (0.35, 0.63)
        ),
    [3, 5, 1])

T4 = ProductType(
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
workers = [
    Worker(1, [1,2]),
    Worker(2, [3,4]), 
    Worker(3, [5,6]),
    Worker(4, [7,8])
    ]

### Poisson Arrivals of Products ###

@resumable function product_arrival(env, product::ProductType, state)
    while true
        # Create job with latest id 
        state.last_job_id += 1 
        id = state.last_job_id
        job = Job(id, product, now(env), 1)

        # Identify the first machine and add it to corresponding queue 
        first_machine = product.route[1]
        push!(state.machine_queues[first_machine], job)

        println("Job $id arrives at M$first_machine at ", now(env))

        trigger_assignment(env, state) # trigger event 

        # poisson timeout until next generation 
        wait_time = randexp() / product.arrival_rate
        @yield timeout(env, wait_time)
    end 
end 




### ALGO ###




env = simulation()

run(env)