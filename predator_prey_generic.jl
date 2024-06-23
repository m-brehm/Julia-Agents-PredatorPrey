using Agents, Random, GLMakie

# needed to check why the prey dies
@enum DeathCause begin
    Starvation
    Predation
end

# for defining animals. most of the fields dont get used directly, but converted to model parameters to change them in GLMakie
mutable struct AnimalDefinition
    n::Int32
    symbol::Char
    color::GLMakie.ColorTypes.RGBA{Float32}
    reproduction_energy_threshold::Int32
    forage_energy_threshold::Int32
    energy_usage::Int32
    reproduction_prob::Float64
    Δenergy::Float64
    perception::Int32
    type::String
    dangers::Vector{String}
    food::Vector{String}
end

# some helper functions to get generated model parameters for animals 
reproduction_prop(a) = abmproperties(model)[Symbol(a.def.type*"_"*"reproduction_prob")]
Δenergy(a) = abmproperties(model)[Symbol(a.def.type*"_"*"Δenergy")]
perception(a) = abmproperties(model)[Symbol(a.def.type*"_"*"perception")]
reproduction_energy_threshold(a) = abmproperties(model)[Symbol(a.def.type*"_"*"reproduction_energy_threshold")]
forage_energy_threshold(a) = abmproperties(model)[Symbol(a.def.type*"_"*"forage_energy_threshold")]
energy_usage(a) = abmproperties(model)[Symbol(a.def.type*"_"*"energy_usage")]

# Animal with AnimalDefinition and fields that change during simulation
# might be better to use @multiagent and @subagent with predator prey as subtypes. Allows to dispatch different functions per kind and change execution order with schedulers.bykind
@agent struct Animal(GridAgent{2})
    energy::Float64
    def::AnimalDefinition
    death_cause::Union{DeathCause,Nothing}
    nearby_dangers
    nearby_food
    scores
end

# get nearby food and danger for later when choosing the next position
function perceive!(a::Animal,model)
    if perception(a) > 0
        nearby = collect(nearby_agents(a, model, perception(a)))
        a.nearby_dangers = map(x -> x.pos, filter(x -> isa(x, Animal) && x.def.type ∈ a.def.dangers, nearby))
        a.nearby_food = map(x -> x.pos, filter(x -> isa(x, Animal) && x.def.type ∈ a.def.food, nearby))
        if "Grass" ∈ a.def.food
            a.nearby_food = [a.nearby_food; nearby_fully_grown(a, model)]
        end
    end
end

# move the animal and subtract energy
function move!(a::Animal,model)
    best_pos = choose_position(a,model)
    if !isnothing(best_pos)
        #make sure predators can step on cells with prey, but prey cannot step on other prey
        ids = ids_in_position(best_pos, model)
        if !isempty(ids) && model[first(ids)].def.type ∈ a.def.food
            move_agent!(a, best_pos, model)
        elseif isempty(best_pos, model)
            move_agent!(a, best_pos, model)
        end
    else
        randomwalk!(a, model)
    end
    a.energy -= energy_usage(a)
end

# choose best position based on scoring
# could have also used the AStar pathfinding from Agents.jl with custom cost_function, but this seemed easier
function choose_position(a::Animal,model)
    scores = []
    positions = push!(collect(nearby_positions(a, model, 1)),a.pos)
    for pos in positions
        score = 0
        for danger in a.nearby_dangers
            distance = findmax(abs.(pos.-danger))[1]
            if distance != 0
                score -= 50/distance
            else
                score -= 100
            end
        end
        for food in a.nearby_food
            if a.energy < forage_energy_threshold(a) 
                distance = findmax(abs.(pos.-food))[1]
                if distance != 0
                    score += 1/distance
                else
                    score += 2
                end
            end
        end
        push!(scores, score)
    end
    a.scores = scores
    return positions[rand(abmrng(model), findall(==(maximum(scores)),scores))]
end

# add energy if predator is on tile with prey, or prey is on tile with grass
function eat!(a::Animal, model)
    prey = first_prey_in_position(a, model)
    if !isnothing(prey)
        #remove_agent!(dinner, model)
        prey.death_cause = Predation
        a.energy += Δenergy(prey)
    end
    if "Grass" ∈ a.def.food && model.fully_grown[a.pos...]
        model.fully_grown[a.pos...] = false
        model.growth[a.pos...] = 0
        a.energy += model.Δenergy_grass
    end
    return
end

# dublicate the animal, based on chance and if it has enough energy
function reproduce!(a::Animal, model)
    if a.energy > reproduction_energy_threshold(a) && rand(abmrng(model)) ≤ reproduction_prop(a)
        a.energy /= 2
        replicate!(a, model)
    end
end

# usefull debug information when hovering over animals in GLMakie
function Agents.agent2string(agent::Animal)
    scores = ""
    f(x) = string(round(x,digits=2))
    if !isempty(agent.scores)
        scores = "\n" * 
                f(agent.scores[6]) * "|" * f(agent.scores[7]) * "|" * f(agent.scores[8]) * "\n" * 
                f(agent.scores[4]) * "|" * f(agent.scores[9]) * "|" * f(agent.scores[5]) * "\n" *
                f(agent.scores[1]) * "|" * f(agent.scores[2]) * "|" * f(agent.scores[3])
    end
    """
    Type = $(agent.def.type)
    ID = $(agent.id)
    energy = $(agent.energy)
    death = $(agent.death_cause)
    scores = $(scores)
    """
end

# helper functions
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
        pos_choice = rand(abmrng(model), positions)
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
        animal_defs = [
            AnimalDefinition(100,'●',RGBAf(1.0, 1.0, 1.0, 0.8),20, 20, 1, 0.3, 6, 1, "Sheep", ["Wolf"], ["Grass"]),
            AnimalDefinition(20,'▲',RGBAf(0.2, 0.2, 0.3, 0.8),20, 20, 1, 0.07, 20, 1, "Wolf", [], ["Sheep"])
        ],
        dims = (20, 20),
        regrowth_time = 30,
        Δenergy_grass = 5,
        seed = 23182,
    )
    rng = MersenneTwister(seed)
    space = GridSpace(dims, periodic = true)
    ## Generate model parameters
    animal_properties = generate_animal_parameters(animal_defs)
    model_properties = Dict(
        :events => events,
        :fully_grown => falses(dims),
        :growth => zeros(Int, dims),
        :regrowth_time => regrowth_time,
        :Δenergy_grass => Δenergy_grass,
    )
    properties = merge(model_properties,animal_properties)
    ## Initialize model
    model = StandardABM(Animal, space; 
        agent_step! = animal_step!, model_step! = model_step!,
        properties, rng, scheduler = Schedulers.Randomly(), warn = false, agents_first = false
    )
    ## Add animals
    for def in animal_defs
        for _ in 1:def.n
            energy = rand(abmrng(model), 1:(def.Δenergy*2)) - 1
            add_agent!(Animal, model, energy, def, nothing, [], [], [])
        end
    end
    ## Add grass with random initial growth
    for p in positions(model)
        fully_grown = rand(abmrng(model), Bool)
        growth = fully_grown ? regrowth_time : rand(abmrng(model), 1:regrowth_time) - 1
        model.growth[p...] = growth
        model.fully_grown[p...] = fully_grown
    end
    return model
end

# Animals move every step and loose energy. If they dont have enough, they die, otherwise they consume energy and reproduce.
# For fair behaviour we move perception into the model step, so every animal makes its decision on one the same state
function animal_step!(a::Animal, model)
    #if !isnothing(a.death_cause)
        #remove_agent!(a, model)
        #return
    #end
    #perceive!(a, model)
    move!(a, model)
    if a.energy < 0
        a.death_cause = Starvation
        return
    end
    eat!(a, model)
    reproduce!(a, model)
end

function model_step!(model)
    handle_event!(model)
    grass_step!(model)
    model_animal_step!(model)
end

function model_animal_step!(model)
    ids = collect(allids(model))
    dead_animals = filter(id -> !isnothing(model[id].death_cause), ids)
    for id in ids
        if !isnothing(model[id].death_cause)
            remove_agent!(id, model)
        else
            perceive!(model[id], model)
        end
    end
end

function grass_step!(model)
    @inbounds for p in positions(model)
        if !(model.fully_grown[p...])
            if model.growth[p...] ≥ model.regrowth_time
                model.fully_grown[p...] = true
            else
                model.growth[p...] += 1
            end
        end
    end
end

function handle_event!(model)
    agents = collect(allagents(model))
    for event in model.events
        if event.timer == event.t_start # start event
            if event.name == "Drought"
                model.regrowth_time = event.value

                predators = filter(a -> !("Grass" ∈ a.def.food), agents)
                for a in predators
                    abmproperties(model)[Symbol(a.def.type*"_"*"perception")] = 2
                end
            
            elseif event.name == "PreyReproduceSeasonal"
                prey = filter(a -> "Grass" ∈ a.def.food, agents)
                for a in prey
                    abmproperties(model)[Symbol(a.def.type*"_"*"reproduction_prob")] = event.value
                end
            
            elseif event.name == "PredatorReproduceSeasonal"
                predators = filter(a -> !("Grass" ∈ a.def.food), agents)
                for a in predators
                    abmproperties(model)[Symbol(a.def.type*"_"*"reproduction_prob")] = event.value
                end

            elseif event.name == "Flood"
                flood_kill_chance = event.value
                for a in agents
                    if (flood_kill_chance ≥ rand(abmrng(model)))
                        remove_agent!(a, model)
                    end
                end

                for p in positions(model)
                    if model.fully_grown[p...]
                        model.growth[p...] = 0
                        model.fully_grown[p...] = false
                    end
                end

            end
        end

        if (event.timer ≥ event.t_start) && (event.timer < event.t_end)
            if event.name == "Drought"
                for p in positions(model)
                    dry_out_chance = 0.4 * (model.growth[p...] / model.regrowth_time)
                    if model.fully_grown[p...] && (dry_out_chance ≥ rand(abmrng(model))) 
                        model.growth[p...] = rand(abmrng(model), 1:model.regrowth_time) - 1
                        model.fully_grown[p...] = false
                    end
                end
            elseif event.name == "Winter" 
                block_field_every = 2
                i = 1
                for p in positions(model)
                    if i % block_field_every == 0
                        model.growth[p...] = 0
                        model.fully_grown[p...] = false
                    end
                    i += 1
                end
                
            end
        end


        if event.timer == event.t_end # end event
            if event.name == "Drought"
                model.regrowth_time = event.pre_value
                predators = filter(id -> !("Grass" ∈ model[id].def.food), agents)
                for id in predators
                    abmproperties(model)[Symbol(model[id].def.type*"_"*"perception")] = 1
                end 

            elseif event.name == "Winter" 
                adjust_field_every = 2
                i = 1
                for p in positions(model)
                    if i % adjust_field_every == 0
                        model.growth[p...] = rand(abmrng(model), 1:(model.regrowth_time))
                        model.fully_grown[p...] = false
                    end
                    i += 1
                end
            
            elseif event.name == "PreyReproduceSeasonal"
                prey = filter(a -> "Grass" ∈ a.def.food, agents)
                for a in prey
                    abmproperties(model)[Symbol(a.def.type*"_"*"reproduction_prob")] = event.pre_value
                end
            
            elseif event.name == "PredatorReproduceSeasonal"
                predators = filter(a -> !("Grass" ∈ a.def.food), agents)
                for a in predators
                    abmproperties(model)[Symbol(a.def.type*"_"*"reproduction_prob")] = event.pre_value
                end

            end
        end

        if event.timer == event.t_cycle # reset timer
            event.timer = 0
        else # continue timer
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
        parameter_dict[Symbol(def.type*"_"*"forage_energy_threshold")]=def.forage_energy_threshold
        parameter_dict[Symbol(def.type*"_"*"reproduction_energy_threshold")]=def.reproduction_energy_threshold
        parameter_dict[Symbol(def.type*"_"*"energy_usage")]=def.energy_usage
    end
    return parameter_dict
end

function generate_animal_parameter_ranges(defs::Vector{AnimalDefinition})
    parameter_range_dict = Dict()
    for def in defs
        parameter_range_dict[Symbol(def.type*"_"*"Δenergy")]=0:1:100
        parameter_range_dict[Symbol(def.type*"_"*"reproduction_prob")]=0:0.01:1
        parameter_range_dict[Symbol(def.type*"_"*"perception")]=0:1:10
        parameter_range_dict[Symbol(def.type*"_"*"forage_energy_threshold")]=0:1:100
        parameter_range_dict[Symbol(def.type*"_"*"reproduction_energy_threshold")]=0:1:100
        parameter_range_dict[Symbol(def.type*"_"*"energy_usage")]=0:1:10
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
