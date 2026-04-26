"""
ATRSC Project - Warehouse optimization
Simulation Instance 3 — FIFO Algorithm
"""

import Pkg
Pkg.add("CairoMakie")
using SimJulia
using ResumableFunctions
using Random
using Statistics
using CairoMakie

env = Simulation()

# --------------------------------------------
#           Data structures
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
    step::Int
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
    product_completion_log::Vector{Tuple{Float64, Int, Float64}}
    worker_job_log::Vector{Tuple{Float64, Float64, Int}}
end

# --------------------------------------------
#       Simulation progression functions
# --------------------------------------------

@resumable function product_arrival(env, product::ProductType, state::SystemState, workers::Vector{Worker})
    while true
        state.last_job_id += 1
        job = Job(state.last_job_id, product, now(env), 1)
        enqueue_job!(state.machine_queues[product.route[1]], job)
        trigger_assignment!(env, state, workers)
        @yield timeout(env, randexp() / product.arrival_rate)
    end
end

function enqueue_job!(queue::Vector{Job}, job::Job)
    lo, hi = 1, length(queue) + 1
    while lo < hi
        mid = (lo + hi) ÷ 2
        queue[mid].arrival <= job.arrival ? lo = mid + 1 : hi = mid
    end
    insert!(queue, lo, job)
end

function progress_job!(env, job::Job, state::SystemState, workers::Vector{Worker})
    job.step += 1
    if job.step > length(job.product.route)
        push!(state.product_completion_log, (now(env), job.product.id, now(env) - job.arrival))
        return
    end
    enqueue_job!(state.machine_queues[job.product.route[job.step]], job)
end

function trigger_assignment!(env, state::SystemState, workers::Vector{Worker})
    for worker in workers
        ev = state.worker_events[worker.id]
        succeed(ev)
        state.worker_events[worker.id] = Event(env)
    end
end

@resumable function execute_job(env, job::Job, machine::Machine, state::SystemState, workers::Vector{Worker}, worker_id::Int)
    a, b = job.product.processing_time[machine.id]
    process_time = rand() * (b - a) + a
    push!(state.worker_job_log, (now(env), process_time, worker_id))
    @yield timeout(env, process_time)
    machine.busy = false
    progress_job!(env, job, state, workers)
    trigger_assignment!(env, state, workers)
end

@resumable function worker_process(env, worker::Worker, state::SystemState, workers::Vector{Worker})
    while true
        job_maybe, mach_maybe = select_job_fifo(worker, state)
        if job_maybe === nothing
            @yield state.worker_events[worker.id]
            continue
        end
        popfirst!(state.machine_queues[mach_maybe.id])
        mach_maybe.busy = true
        @yield @process execute_job(env, job_maybe::Job, mach_maybe::Machine, state, workers, worker.id)
    end
end

# -------------------------------------
#     FIFO worker decision
# -------------------------------------

function select_job_fifo(worker::Worker, state::SystemState)
    selected_job     = nothing
    selected_machine = nothing
    earliest_arrival = Inf
    for machine in worker.qualifications
        machine.busy && continue
        queue = state.machine_queues[machine.id]
        if !isempty(queue) && queue[1].arrival < earliest_arrival
            earliest_arrival = queue[1].arrival
            selected_job     = queue[1]
            selected_machine = machine
        end
    end
    return selected_job, selected_machine
end

# -------------------------------------
#     Steady-state detection
# -------------------------------------

function detect_steady_state(times, values; window=20, tol=0.05)
    n = length(values)
    for i in (2*window):n
        m1 = mean(values[i-window+1:i])
        m2 = mean(values[i-2*window+1:i-window])
        if abs(m1 - m2) < tol
            return times[i]
        end
    end
    return nothing
end

# -------------------------------------
#           Dossier
# -------------------------------------

function save_dossier(state::SystemState, workers::Vector{Worker}, t_ss::Float64, simulation_time::Float64, instance_id::Int)
    measurement_period = simulation_time - t_ss

    ss_jobs       = filter(x -> x[1] >= t_ss, state.product_completion_log)
    ss_worker_log = filter(x -> x[1] >= t_ss, state.worker_job_log)

    fig = Figure(size = (1200, 500))

    ax1 = Axis(fig[1, 1],
        title  = "Instance I$(instance_id) — Avg Time in System per Product",
        xlabel = "Product Type", ylabel = "Avg Time in System")
    avgs = [begin
        pts = filter(x -> x[2] == p, ss_jobs)
        isempty(pts) ? 0.0 : mean(x[3] for x in pts)
    end for p in 1:4]
    barplot!(ax1, collect(1:4), avgs, color = :steelblue)

    ax2 = Axis(fig[1, 2],
        title  = "Instance I$(instance_id) — Worker Utilization",
        xlabel = "Worker", ylabel = "Proportion of time working")
    worker_ids = [w.id for w in sort(workers, by = w -> w.id)]
    utils = [begin
        busy = sum((x[2] for x in ss_worker_log if x[3] == wid), init = 0.0)
        busy / measurement_period
    end for wid in worker_ids]
    barplot!(ax2, worker_ids, utils, color = :coral)
    ylims!(ax2, 0, 1)

    fname = "dossier_I$(instance_id).png"
    save(fname, fig)
end

#--------------------------------------------------------------------------------------------
#                                   SIMULATION LAUNCH
#--------------------------------------------------------------------------------------------

T1 = ProductType(1, 0.29,
    Dict(1 => (0.58, 0.78), 2 => (0.23, 0.56), 3 => (0.81, 0.93), 4 => (0.12, 0.39), 8 => (0.82, 1.04)),
    [1, 2, 3, 4, 8])

T2 = ProductType(2, 0.32,
    Dict(2 => (0.59, 0.68), 4 => (0.74, 0.77), 7 => (0.3, 0.55)),
    [2, 4, 7])

T3 = ProductType(3, 0.47,
    Dict(1 => (0.57, 0.64), 3 => (0.37, 0.54), 5 => (0.35, 0.63)),
    [3, 5, 1])

T4 = ProductType(4, 0.38,
    Dict(5 => (0.36, 0.51), 6 => (0.61, 0.7), 7 => (0.78, 0.85), 8 => (0.18, 0.37)),
    [5, 6, 7, 8])

M1 = Machine(1, false); M2 = Machine(2, false); M3 = Machine(3, false); M4 = Machine(4, false)
M5 = Machine(5, false); M6 = Machine(6, false); M7 = Machine(7, false); M8 = Machine(8, false)

# Workers — Instance I3
workers = [
    Worker(1, [M1, M2]),
    Worker(2, [M3]),
    Worker(3, [M4, M6]),
    Worker(4, [M5, M8]),
    Worker(5, [M3, M6]),
    Worker(6, [M1, M7])
]

simulation_time = 1000.0

product_completion_log = Tuple{Float64, Int, Float64}[]
worker_job_log         = Tuple{Float64, Float64, Int}[]
machine_queues         = Dict(i => Job[] for i in 1:8)
worker_events          = Dict(w.id => Event(env) for w in workers)
state = SystemState(machine_queues, 0, worker_events, product_completion_log, worker_job_log)

@process product_arrival(env, T1, state, workers)
@process product_arrival(env, T2, state, workers)
@process product_arrival(env, T3, state, workers)
@process product_arrival(env, T4, state, workers)
for worker in workers
    @process worker_process(env, worker, state, workers)
end

run(env, simulation_time)

# ---- STEADY-STATE DETECTION ----

log_sorted     = sort(state.product_completion_log, by = x -> x[1])
comp_times     = [x[1] for x in log_sorted]
comp_durations = [x[3] for x in log_sorted]

t_ss_maybe = detect_steady_state(comp_times, comp_durations)
t_ss = t_ss_maybe === nothing ? (println("WARNING: steady state not detected, using t=0"); 0.0) : t_ss_maybe

# ---- METRICS (steady-state only) ----

measurement_period = simulation_time - t_ss
ss_jobs       = filter(x -> x[1] >= t_ss, log_sorted)
ss_worker_log = filter(x -> x[1] >= t_ss, state.worker_job_log)

println("\n--- Per-product avg time in system ---")
for p in 1:4
    pts = filter(x -> x[2] == p, ss_jobs)
    isempty(pts) && continue
    println("  Product $p: $(round(mean(x[3] for x in pts), digits=4))")
end

all_durations = [x[3] for x in ss_jobs]
if !isempty(all_durations)
    println("  Global avg time in system: $(round(mean(all_durations), digits=4))")
end

println("\n--- Worker utilization ---")
for w in sort(workers, by = w -> w.id)
    busy = sum((x[2] for x in ss_worker_log if x[3] == w.id), init = 0.0)
    println("  Worker $(w.id): $(round(busy / measurement_period, digits=4))")
end

save_dossier(state, workers, t_ss, simulation_time, 3)
