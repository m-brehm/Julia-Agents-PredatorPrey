using Agents, Random, GLMakie

@enum DeathCause begin
    Starvation
    Predation
end
mutable struct AnimalDefinition
    symbol::Char
    color::GLMakie.ColorTypes.RGBA{Float32}
    energy_threshold::Float64
    reproduction_prob::Float64
    Δenergy::Float64
    perception::Int32
    type::String
    dangers::Vector{String}
    food::Vector{String}
end
reproduction_prop(a) = abmproperties(model)[Symbol(a.def.type*"_"*"reproduction_prob")]
Δenergy(a) = abmproperties(model)[Symbol(a.def.type*"_"*"Δenergy")]
perception(a) = abmproperties(model)[Symbol(a.def.type*"_"*"perception")]
energy_threshold(a) = abmproperties(model)[Symbol(a.def.type*"_"*"energy_threshold")]
struct StartDefinition
    n::Int32
    def::AnimalDefinition
end
#might be better to use @multiagent and @subagent with predator prey as subtypes. Allows to dispatch different functions per kind and change execution order with schedulers.bykind
@agent struct Animal(GridAgent{2})
    energy::Float64
    def::AnimalDefinition
    death_cause::Union{DeathCause,Nothing}
    nearby_dangers
    nearby_food
end


function perceive!(a::Animal,model)
    if perception(a) > 0
        nearby = collect(nearby_agents(a, model, perception(a)))
        a.nearby_dangers = map(x -> x.pos, filter(x -> isa(x, Animal) && x.def.type ∈ a.def.dangers && isnothing(x.death_cause), nearby))
        a.nearby_food = map(x -> x.pos, filter(x -> isa(x, Animal) && x.def.type ∈ a.def.food && isnothing(x.death_cause), nearby))
        if "Grass" ∈ a.def.food
            a.nearby_food = [a.nearby_food; nearby_fully_grown(a, model)]
        end
    end
end
function move!(a::Animal,model)
    best_pos = calculate_best_pos(a,model)
    if !isnothing(best_pos)
        #make sure predators can step on cells with prey by setting ifempty to false
        ids = ids_in_position(best_pos, model)
        if !isempty(ids) && model[first(ids)].def.type ∈ a.def.food
            move_towards!(a, best_pos, model; ifempty = false)
        else
            move_towards!(a, best_pos, model)
        end
    else
        randomwalk!(a, model)
    end
    a.energy -= 1
end
function calculate_best_pos(a::Animal,model)
    danger_scores = []
    food_scores = []
    positions = collect(nearby_positions(a, model, 1))
    # weight scores with utility functions
    for pos in positions
        if !isempty(a.nearby_dangers)
            danger_score = sum(map(danger -> findmax(abs.(pos.-danger))[1], a.nearby_dangers))
            push!(danger_scores,danger_score)
        end
        if !isempty(a.nearby_food)
            food_score = sum(map(food -> findmax(abs.(pos.-food))[1], a.nearby_food))
            push!(food_scores,food_score)
        end
    end
    #findall(==(minimum(x)),x) to find all mins
    #best to filter out all positions where there is already an agent and take into account the current position, so sheeps dont just stand still when the position is occupied
    if !isempty(a.nearby_dangers) #&& a.energy > a.def.energy_threshold  
        safest_position = positions[findmax(danger_scores)[2]]
        return safest_position
    elseif !isempty(a.nearby_food) #&& a.energy < a.def.energy_threshold  
        foodiest_position = positions[findmin(food_scores)[2]]
        return foodiest_position
    else
        return nothing
    end
end
function eat!(a::Animal, model)
    prey = first_prey_in_position(a, model)
    if !isnothing(prey)
        #remove_agent!(dinner, model)
        prey.death_cause = Predation
        a.energy += Δenergy(prey)
    end
    if "Grass" ∈ a.def.food && model.fully_grown[a.pos...]
        model.fully_grown[a.pos...] = false
        a.energy += model.Δenergy_grass
    end
    return
end
function reproduce!(a::Animal, model)
    if a.energy > energy_threshold(a) && rand(abmrng(model)) ≤ reproduction_prop(a)#a.def.reproduction_prob
        a.energy /= 2
        replicate!(a, model)
    end
end

function Agents.agent2string(agent::Animal)
    """
    Type = $(agent.def.type)
    ID = $(agent.id)
    energy = $(agent.energy)
    perception = $(agent.def.perception)
    death = $(agent.death_cause)
    """
end

function move_away!(agent, pos, model)
    direction = agent.pos .- pos
    direction = clamp.(direction,-1,1)
    walk!(agent,direction,model)
end
function move_towards!(agent, pos, model; ifempty=true)
    direction = pos .- agent.pos
    direction = clamp.(direction,-1,1)
    walk!(agent,direction,model; ifempty=ifempty)
end
function nearby_fully_grown(a::Animal, model)
    nearby_pos = nearby_positions(a.pos, model, perception(a))
    fully_grown_positions = filter(x -> model.fully_grown[x...], collect(nearby_pos))
    return fully_grown_positions
end
function random_empty_fully_grown(positions, model)
    n_attempts = 2*length(positions)
    while n_attempts != 0
        pos_choice = rand(positions)
        isempty(pos_choice, model) && return pos_choice
        n_attempts -= 1
    end
    return positions[1]
end
function first_prey_in_position(a, model)
    ids = ids_in_position(a.pos, model)
    j = findfirst(id -> model[id] isa Animal && model[id].def.type ∈ a.def.food && isnothing(model[id].death_cause), ids)
    isnothing(j) ? nothing : model[ids[j]]::Animal
end

function initialize_model(;
        events = [],
        start_defs = [
            StartDefinition(100,AnimalDefinition('●',RGBAf(1.0, 1.0, 1.0, 0.8),20, 0.3, 6, 1, "Sheep", ["Wolf"], ["Grass"])),
            StartDefinition(20,AnimalDefinition('▲',RGBAf(0.2, 0.2, 0.3, 0.8),20, 0.07, 20, 1, "Wolf", [], ["Sheep"]))
        ],
        dims = (20, 20),
        regrowth_time = 30,
        Δenergy_sheep = 4,
        Δenergy_wolf = 20,
        Δenergy_grass = 5,
        sheep_reproduce = 0.04,
        wolf_reproduce = 0.05,
        sheep_perception = 0,
        wolf_perception = 0,
        seed = 23182,
    )
    rng = MersenneTwister(seed)
    space = GridSpace(dims, periodic = true)
    ## Model properties contain the grass as two arrays: whether it is fully grown
    ## and the time to regrow. Also have static parameter `regrowth_time`.
    ## Notice how the properties are a `NamedTuple` to ensure type stability.
    ## define as dictionary(mutable) instead of tuples(immutable) as per https://github.com/JuliaDynamics/Agents.jl/issues/727
    ## maybe instead of AnimalDefinition we build the properties dict dynamically and use model properties during the simulation
    animal_defs = Vector{AnimalDefinition}()
    for start_def in start_defs
        push!(animal_defs,start_def.def)
    end
    animal_properties = generate_animal_parameters(animal_defs)
    properties = Dict(
        :events => events,
        :fully_grown => falses(dims),
        :countdown => zeros(Int, dims),
        :regrowth_time => regrowth_time,
        :Δenergy_grass => Δenergy_grass,
    )
    properties = merge(properties,animal_properties)
    model = StandardABM(Animal, space; 
        agent_step! = animal_step!, model_step! = model_step!,
        properties, rng, scheduler = Schedulers.Randomly(), warn = false, agents_first = false
    )
    for start_def in start_defs
        for _ in 1:start_def.n
            energy = rand(abmrng(model), 1:(start_def.def.Δenergy*2)) - 1
            add_agent!(Animal, model, energy, start_def.def, nothing, [], [])
        end
    end
    ## Add grass with random initial growth
    for p in positions(model)
        fully_grown = rand(abmrng(model), Bool)
        countdown = fully_grown ? regrowth_time : rand(abmrng(model), 1:regrowth_time) - 1
        model.countdown[p...] = countdown
        model.fully_grown[p...] = fully_grown
    end
    return model
end

# ## Defining the stepping functions
# Sheep and wolves behave similarly:
# both lose 1 energy unit by moving to an adjacent position and both consume
# a food source if available. If their energy level is below zero, they die.
# Otherwise, they live and reproduce with some probability.
# They move to a random adjacent position with the [`randomwalk!`](@ref) function.

# Notice how the function `sheepwolf_step!`, which is our `agent_step!`,
# is dispatched to the appropriate agent type via Julia's Multiple Dispatch system.

function animal_step!(a::Animal, model)
    if !isnothing(a.death_cause)
        #remove_agent!(a, model)
        #return
    end
    perceive!(a, model)
    move!(a, model)
    if a.energy < 0
        a.death_cause = Starvation
        return
    end
    eat!(a, model)
    reproduce!(a, model)
end

function model_step!(model)
    event_handler!(model)
    grass_step!(model)
end

# The behavior of grass function differently. If it is fully grown, it is consumable.
# Otherwise, it cannot be consumed until it regrows after a delay specified by
# `regrowth_time`. The dynamics of the grass is our `model_step!` function.
function grass_step!(model)
    ids = collect(allids(model))
    dead_animals = filter(id -> !isnothing(model[id].death_cause), ids)
    for a in dead_animals
        remove_agent!(a, model)
    end
    @inbounds for p in positions(model) # we don't have to enable bound checking
        if !(model.fully_grown[p...])
            if model.countdown[p...] ≤ 0
                model.fully_grown[p...] = true
                model.countdown[p...] = model.regrowth_time
            else
                model.countdown[p...] -= 1
            end
        end
    end
end

# Check current step and start event at step t
function event_handler!(model)
    ids = collect(allids(model))
    for event in model.events
        if event.timer == event.t_start # start event
            if event.name == "Drought"
                model.regrowth_time = event.value
                for id in ids
                    model[id].def.perception += 1
                end
                
            elseif event.name == "Flood"
                model.regrowth_time = event.value
                for id in ids
                    model[id].def.Δenergy -= 1
                end
            
            elseif event.name == "PreyReproduceSeasonal"
                prey = filter(id -> "Grass" ∈ model[id].def.food, ids)
                for id in prey
                    model[id].def.reproduction_prob = event.value
                end
            
            elseif event.name == "PredatorReproduceSeasonal"
                predators = filter(id -> !("Grass" ∈ model[id].def.food), ids)
                for id in predators
                    model[id].def.reproduction_prob = event.value
                end

            end
        end

        if event.timer == event.t_end # end event
            if event.name == "Drought"
                model.regrowth_time = event.pre_value
                for id in ids
                    model[id].def.perception -= 1
                end

            elseif event.name == "Flood"
                model.regrowth_time = event.pre_value
                for id in ids
                    model[id].def.Δenergy += 1
                end
            
            elseif event.name == "PreyReproduceSeasonal"
                prey = filter(id -> "Grass" ∈ model[id].def.food, ids)
                for id in prey
                    model[id].def.reproduction_prob = event.pre_value
                end
            
            elseif event.name == "PredatorReproduceSeasonal"
                predators = filter(id -> !("Grass" ∈ model[id].def.food), ids)
                for id in predators
                    model[id].def.reproduction_prob = event.pre_value
                end

            end
        end

        if event.timer == event.t_cycle # reset cycle
            event.timer = 1
        else
            event.timer += 1
        end
    end
end

function generate_animal_parameters(defs::Vector{AnimalDefinition})
    parameter_dict = Dict()
    for def in defs
        parameter_dict[Symbol(def.type*"_"*"Δenergy")]=def.Δenergy
        parameter_dict[Symbol(def.type*"_"*"reproduction_prob")]=def.reproduction_prob
        parameter_dict[Symbol(def.type*"_"*"perception")]=def.perception
        parameter_dict[Symbol(def.type*"_"*"energy_threshold")]=def.energy_threshold
    end
    return parameter_dict
end

function generate_animal_parameter_ranges(defs::Vector{AnimalDefinition})
    parameter_range_dict = Dict()
    for def in defs
        parameter_range_dict[Symbol(def.type*"_"*"Δenergy")]=0:1:100
        parameter_range_dict[Symbol(def.type*"_"*"reproduction_prob")]=0:0.01:1
        parameter_range_dict[Symbol(def.type*"_"*"perception")]=0:1:10
        parameter_range_dict[Symbol(def.type*"_"*"energy_threshold")]=0:1:100
    end
    return parameter_range_dict
end


mutable struct RecurringEvent
    name::String
    value::Float64
    pre_value::Float64
    t_start::Int64
    t_end::Int64
    t_cycle::Int64
    timer::Int64
end
