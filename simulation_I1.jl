"""
ATRSC Project - Warehouse optimization 
Simulation Instance 1 
FIFO Algorithm
"""

# Builtin simulator import
using SimJulia
using ResumableFunctions
using Random

env = Simulation()

# --------------------------------------------
#           Data structures components 
# --------------------------------------------

struct ProductType
    id::Int
    arrival_rate::Float64
    processing_time::Dict{Int,Tuple{Float64, Float64}}
    route::Vector{Int}
end

mutable struct Job 
    id::Int
    product::ProductType
    arrival::Float64
    step::Int # where we are in the route
end

mutable struct Machine 
    id::Int
    busy::Bool 
end 

struct Worker 
    id::Int 
    qualifications::Vector{Machine}
end 

mutable struct SystemState
    machine_queues::Dict{Int, Vector{Job}}
    last_job_id::Int
    worker_events::Dict{Int, Event}
end 


# --------------------------------------------
#       Poisson Arrivals of Products 
# --------------------------------------------

@resumable function product_arrival(env, product::ProductType, state::SystemState, workers::Vector{Worker})
    """
    Poisson arrival of products, each arrival creates a new job
    places it in the queue of first machine in product route 
    sends trigger to workers for possible action 
    """
    while true
        state.last_job_id += 1
        id = state.last_job_id

        job = Job(id, product, now(env), 1)

        first_machine = product.route[1]
        enqueue_job!(state.machine_queues[first_machine], job)

        println("Job $(job.id) ARRIVES at M$(first_machine) at ", now(env))

        trigger_assignment!(env, state, workers)

        wait_time = randexp() / product.arrival_rate
        @yield timeout(env, wait_time)
    end
end

### Simulation progression functions ###

function enqueue_job!(queue::Vector{Job}, job::Job)
    """
    Insert a job maintaining arrival-time order (oldest first).
    push! gives insertion-time order, which diverges from arrival-time order
    once jobs route through multiple machines: a job that arrived early but
    spent time at prior machines is pushed AFTER newer jobs already queued
    here, making queue[1].arrival wrong for FIFO selection.
    """
    lo, hi = 1, length(queue) + 1
    while lo < hi
        mid = (lo + hi) ÷ 2
        queue[mid].arrival <= job.arrival ? lo = mid + 1 : hi = mid
    end
    insert!(queue, lo, job)
end

function progress_job!(env, job::Job, state::SystemState)
    """
    Progresses a job from a step to another, updating the machine queues and logging the time spent in the system
    """
    job.step += 1 # progress one step further

    # finished job case
    if job.step > length(job.product.route)
        time_in_system = now(env) - job.arrival
        println("Job $(job.id) completed at timestamp", now(env), " | Spent", time_in_system, "in system")
        return
    end

    # moving to next step case
    next_step_machine = job.product.route[job.step]
    enqueue_job!(state.machine_queues[next_step_machine], job)
    println("Job $(job.id) pending on machine", next_step_machine, " at timestamp", now(env))
end

function trigger_assignment!(env, state::SystemState, workers::Vector{Worker})
    """Wake up all workers for possible reassignment on tasks everytime an event happens in the System"""
    for worker in workers
        ev = state.worker_events[worker.id]
        succeed(ev) # Wakes the worker if currently waiting on ev 
        state.worker_events[worker.id] = Event(env)
    end
end

@resumable function execute_job(env, job::Job, machine::Machine, state::SystemState, workers::Vector{Worker}, worker_id::Int)
    """
    Execute one job on one machine, then advance it.
    Splitting this out from worker_process is the only reliable fix for this version of
    ResumableFunctions: the macro's variable-substitution pass treats all code after a
    generated `return` (i.e. after @yield) as dead, so local variables like job_maybe
    are never rewritten to struct-field accesses and are undefined on resume.
    Function PARAMETERS, by contrast, are written into the struct at construction time
    and are always available across any @yield — no substitution pass needed.
    """
    println(
        " worker n° ", worker_id,
        " starts job ", job.id,
        " at timestamp ", now(env),
        " on machine ", machine.id
    )

    a, b = job.product.processing_time[machine.id]
    process_time = rand() * (b - a) + a

    @yield timeout(env, process_time)

    println(
        " worker n° ", worker_id,
        " finished job ", job.id,
        " at timestamp ", now(env),
        " on machine ", machine.id
    )

    machine.busy = false
    progress_job!(env, job, state)
    trigger_assignment!(env, state, workers)
end

@resumable function worker_process(env, worker::Worker, state::SystemState, workers::Vector{Worker})
    """ Fully event driven process for worker """
    while true
        _sel       = select_job_fifo(worker, state)
        job_maybe  = _sel[1]
        mach_maybe = _sel[2]

        if job_maybe === nothing
            @yield state.worker_events[worker.id]
            continue
        end

        # Remove from queue and mark busy before spawning subprocess.
        # job_maybe and mach_maybe are NOT used after the @yield below,
        # so they are not cross-yield variables — no substitution issue.
        popfirst!(state.machine_queues[mach_maybe.id])
        mach_maybe.busy = true

        @yield @process execute_job(env, job_maybe::Job, mach_maybe::Machine, state, workers, worker.id)
    end
end

# -------------------------------------
#     FIFO ALGO FOR WORKER DECISION
# -------------------------------------

function select_job_fifo(worker::Worker, state::SystemState)
    """
    Worker decision algorithm (FIFO Based): 
    Once finished a task, he looks for the job that has been waiting for the longest among the machines 
    that he is able to work on and that are waiting for a worker to resume
    """
    selected_job = nothing
    selected_machine = nothing 
    earliest_arrival = Inf

    for machine in worker.qualifications 
        machine_id = machine.id

        if machine.busy 
            continue 
        end 

        # Finding longest pending job within the possibles 
        queue = state.machine_queues[machine_id]
        if !isempty(queue)
            job = queue[1]
            if job.arrival < earliest_arrival
                earliest_arrival = job.arrival
                selected_job = job
                selected_machine = machine
            end 
        end 
    end 
    return selected_job, selected_machine
end 


#--------------------------------------------------------------------------------------------
#                                       SIMULATION LAUNCH 
#--------------------------------------------------------------------------------------------

# ---------------------
#       Instances 
# ---------------------

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

M1 = Machine(1, false)
M2 = Machine(2, false)
M3 = Machine(3, false)
M4 = Machine(4, false)
M5 = Machine(5, false)
M6 = Machine(6, false)
M7 = Machine(7, false)
M8 = Machine(8, false)

# Workers for Instance I1 
workers = [
    Worker(1, [M1,M2]),
    Worker(2, [M3,M4]), 
    Worker(3, [M5,M6]),
    Worker(4, [M7,M8])
    ]

machine_queues = Dict(i => Job[] for i in 1:8)
worker_events = Dict(w.id => Event(env) for w in workers)
state = SystemState(machine_queues, 0, worker_events)

# ----------------------------
#           Processes 
# ----------------------------

# Start product spawns 
@process product_arrival(env, T1, state, workers)
@process product_arrival(env, T2, state, workers)
@process product_arrival(env, T3, state, workers)
@process product_arrival(env, T4, state, workers)
# Start workers activity 
for worker in workers 
    @process worker_process(env, worker, state, workers)
end 

run(env, 100.0) # Running 100 simulation steps 