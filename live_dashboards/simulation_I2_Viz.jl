"""
ATRSC Project - Warehouse optimization
Simulation Instance 2 — FIFO Algorithm — Live Dashboard
"""

import Pkg
Pkg.add("GLMakie")
using SimJulia
using ResumableFunctions
using Random
using Statistics
using GLMakie

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

#--------------------------------------------------------------------------------------------
#                                       DASHBOARD
#--------------------------------------------------------------------------------------------

mutable struct DashboardState
    queue_lengths::Observable{Vector{Int}}
    worker_busy::Observable{Vector{Bool}}
    avg_time_in_system::Observable{Vector{Float64}}
    avg_queue_length::Observable{Vector{Float64}}
    simulation_times::Observable{Vector{Float64}}
end

function init_dashboard_state(n_machines::Int, n_workers::Int)
    DashboardState(
        Observable(fill(0, n_machines)),
        Observable(fill(false, n_workers)),
        Observable(Float64[]),
        Observable(Float64[]),
        Observable(Float64[])
    )
end

function update_queue_lengths!(dash::DashboardState, state::SystemState)
    dash.queue_lengths[] = [length(state.machine_queues[i]) for i in 1:length(dash.queue_lengths[])]
    sleep(0.02)
end

function set_worker_busy!(dash::DashboardState, worker_id::Int, is_busy::Bool)
    status = copy(dash.worker_busy[])
    status[worker_id] = is_busy
    dash.worker_busy[] = status
    sleep(0.02)
end

function update_metrics!(dash::DashboardState, state::SystemState, env)
    all_times = [x[3] for x in state.product_completion_log]
    avg_time  = isempty(all_times) ? 0.0 : mean(all_times)

    total_queue = sum(length(q) for q in values(state.machine_queues))
    avg_queue   = total_queue / length(state.machine_queues)

    current_time = now(env)
    times_vec = dash.simulation_times[]
    if isempty(times_vec) || (current_time - times_vec[end]) >= 0.1
        dash.simulation_times[]   = push!(copy(times_vec), current_time)
        dash.avg_time_in_system[] = push!(copy(dash.avg_time_in_system[]), avg_time)
        dash.avg_queue_length[]   = push!(copy(dash.avg_queue_length[]), avg_queue)
    end
end

function build_dashboard(dash::DashboardState)
    fig = Figure(size = (1400, 900))

    ax1 = Axis(fig[1, 1], title = "Queue lengths per machine", xlabel = "Machine", ylabel = "Queue length")
    barplot!(ax1, 1:length(dash.queue_lengths[]), dash.queue_lengths)
    ylims!(ax1, 0, nothing)

    ax2 = Axis(fig[1, 2], title = "Average Time in System", xlabel = "Simulation Time", ylabel = "Avg Time")
    lines!(ax2, dash.simulation_times, dash.avg_time_in_system, color = :blue, linewidth = 2)

    ax3 = Axis(fig[2, 1], title = "Worker activity (green=idle, red=busy)", xlabel = "Worker", ylabel = "")
    worker_colors = @lift [b ? :red : :green for b in $(dash.worker_busy)]
    scatter!(ax3, 1:length(dash.worker_busy[]), ones(length(dash.worker_busy[])), color = worker_colors, markersize = 80)
    ylims!(ax3, 0.5, 1.5)
    hidedecorations!(ax3, ticks = false, ticklabels = false, label = false)

    ax4 = Axis(fig[2, 2], title = "Average Queue Length", xlabel = "Simulation Time", ylabel = "Avg Queue Length")
    lines!(ax4, dash.simulation_times, dash.avg_queue_length, color = :orange, linewidth = 2)

    screen = display(fig)
    return fig, screen
end

# --------------------------------------------
#       Simulation progression functions
# --------------------------------------------

@resumable function product_arrival(env, product::ProductType, state::SystemState, workers::Vector{Worker}, dash::DashboardState)
    while true
        state.last_job_id += 1
        job = Job(state.last_job_id, product, now(env), 1)
        enqueue_job!(state.machine_queues[product.route[1]], job)
        update_queue_lengths!(dash, state)
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

function progress_job!(env, job::Job, state::SystemState, workers::Vector{Worker}, dash::DashboardState)
    job.step += 1
    if job.step > length(job.product.route)
        push!(state.product_completion_log, (now(env), job.product.id, now(env) - job.arrival))
        update_metrics!(dash, state, env)
        return
    end
    enqueue_job!(state.machine_queues[job.product.route[job.step]], job)
    update_queue_lengths!(dash, state)
end

function trigger_assignment!(env, state::SystemState, workers::Vector{Worker})
    for worker in workers
        ev = state.worker_events[worker.id]
        succeed(ev)
        state.worker_events[worker.id] = Event(env)
    end
end

@resumable function execute_job(env, job::Job, machine::Machine, state::SystemState, workers::Vector{Worker}, worker_id::Int, dash::DashboardState)
    set_worker_busy!(dash, worker_id, true)
    a, b = job.product.processing_time[machine.id]
    process_time = rand() * (b - a) + a
    push!(state.worker_job_log, (now(env), process_time, worker_id))
    @yield timeout(env, process_time)
    machine.busy = false
    set_worker_busy!(dash, worker_id, false)
    progress_job!(env, job, state, workers, dash)
    trigger_assignment!(env, state, workers)
end

@resumable function worker_process(env, worker::Worker, state::SystemState, workers::Vector{Worker}, dash::DashboardState)
    while true
        job_maybe, mach_maybe = select_job_fifo(worker, state)
        if job_maybe === nothing
            @yield state.worker_events[worker.id]
            continue
        end
        popfirst!(state.machine_queues[mach_maybe.id])
        mach_maybe.busy = true
        @yield @process execute_job(env, job_maybe::Job, mach_maybe::Machine, state, workers, worker.id, dash)
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

    save("dossier_I$(instance_id).png", fig)
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

# Workers — Instance I2
workers = [
    Worker(1, [M1, M3, M6]),
    Worker(2, [M2, M5, M7, M8]),
    Worker(3, [M2, M4, M5, M8]),
    Worker(4, [M1, M3, M4, M6, M7])
]

simulation_time = 200.0

product_completion_log = Tuple{Float64, Int, Float64}[]
worker_job_log         = Tuple{Float64, Float64, Int}[]
machine_queues         = Dict(i => Job[] for i in 1:8)
worker_events          = Dict(w.id => Event(env) for w in workers)
state = SystemState(machine_queues, 0, worker_events, product_completion_log, worker_job_log)

dash = init_dashboard_state(8, length(workers))
fig, screen = build_dashboard(dash)
update_queue_lengths!(dash, state)

@process product_arrival(env, T1, state, workers, dash)
@process product_arrival(env, T2, state, workers, dash)
@process product_arrival(env, T3, state, workers, dash)
@process product_arrival(env, T4, state, workers, dash)
for worker in workers
    @process worker_process(env, worker, state, workers, dash)
end

run(env, simulation_time)

# ---- STEADY-STATE DETECTION & METRICS ----

log_sorted     = sort(state.product_completion_log, by = x -> x[1])
comp_times     = [x[1] for x in log_sorted]
comp_durations = [x[3] for x in log_sorted]

t_ss_maybe = detect_steady_state(comp_times, comp_durations)
t_ss = t_ss_maybe === nothing ? (println("WARNING: steady state not detected, using t=0"); 0.0) : t_ss_maybe

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
    println("  Global avg: $(round(mean(all_durations), digits=4))")
end

println("\n--- Worker utilization ---")
for w in sort(workers, by = w -> w.id)
    busy = sum((x[2] for x in ss_worker_log if x[3] == w.id), init = 0.0)
    println("  Worker $(w.id): $(round(busy / measurement_period, digits=4))")
end

save_dossier(state, workers, t_ss, simulation_time, 2)

wait(screen)
