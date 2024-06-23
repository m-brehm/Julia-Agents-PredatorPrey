using Agents, Random, GLMakie

@enum DeathCause begin
    Starvation
    Predation
end
mutable struct AnimalDefinition
    n::Int32
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
#might be better to use @multiagent and @subagent with predator prey as subtypes. Allows to dispatch different functions per kind and change execution order with schedulers.bykind
@agent struct Animal(GridAgent{2})
    energy::Float64
    def::AnimalDefinition
    death_cause::Union{DeathCause,Nothing}
    nearby_dangers
    nearby_food
    food_scores
    danger_scores
end


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
        danger_score = 0
        for danger in a.nearby_dangers
            distance = findmax(abs.(pos.-danger))[1]
            if distance != 0
                danger_score=danger_score-1/distance
            else
                danger_score-=2
            end
        end
        food_score = 0
        for food in a.nearby_food
            distance = findmax(abs.(pos.-food))[1]
            if distance != 0
                food_score=food_score+1/distance
            else
                food_score+=2
            end
        end
        push!(danger_scores,danger_score)
        push!(food_scores,food_score)
    end
    a.danger_scores = danger_scores
    a.food_scores = food_scores
    #findall(==(minimum(x)),x) to find all mins
    #best to filter out all positions where there is already an agent and take into account the current position, so sheeps dont just stand still when the position is occupied
    if !isempty(a.nearby_dangers) #&& a.energy > a.def.energy_threshold  
        safest_position = positions[findmax(danger_scores)[2]]
        return safest_position
    elseif !isempty(a.nearby_food) #&& a.energy < a.def.energy_threshold  
        foodiest_position = positions[findmax(food_scores)[2]]
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
        model.growth[a.pos...] = 0
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
    food_scores = ""
    danger_scores = ""
    f(x) = string(round(x,digits=2))
    if !isempty(agent.food_scores)
        food_scores = "\n" * f(agent.food_scores[6]) * "|" * f(agent.food_scores[7]) * "|" * f(agent.food_scores[8]) * "\n" * 
               f(agent.food_scores[4]) * "|" * "  " * "|" * f(agent.food_scores[5]) * "\n" *
               f(agent.food_scores[1]) * "|" * f(agent.food_scores[2]) * "|" * f(agent.food_scores[3])
    end
    if !isempty(agent.danger_scores)
        danger_scores = "\n" * f(agent.danger_scores[6]) * "|" * f(agent.danger_scores[7]) * "|" * f(agent.danger_scores[8]) * "\n" * 
               f(agent.danger_scores[4]) * "|" * "  " * "|" * f(agent.danger_scores[5]) * "\n" *
               f(agent.danger_scores[1]) * "|" * f(agent.danger_scores[2]) * "|" * f(agent.danger_scores[3])
    end
    """
    Type = $(agent.def.type)
    ID = $(agent.id)
    energy = $(agent.energy)
    perception = $(agent.def.perception)
    death = $(agent.death_cause)
    food_scores = $(food_scores)
    danger_scores = $(danger_scores)
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
        animal_defs = [
            AnimalDefinition(100,'●',RGBAf(1.0, 1.0, 1.0, 0.8),20, 0.3, 6, 1, "Sheep", ["Wolf"], ["Grass"]),
            AnimalDefinition(20,'▲',RGBAf(0.2, 0.2, 0.3, 0.8),20, 0.07, 20, 1, "Wolf", [], ["Sheep"])
        ],
        dims = (20, 20),
        regrowth_time = 30,
        Δenergy_grass = 5,
        seed = 23182,
    )
    rng = MersenneTwister(seed)
    space = GridSpace(dims, periodic = true)
    ## Model properties contain the grass as two arrays: whether it is fully grown
    ## and the time to regrow. Also have static parameter `regrowth_time`.
    ## Notice how the properties are a `NamedTuple` to ensure type stability.
    ## define as dictionary(mutable) instead of tuples(immutable) as per https://github.com/JuliaDynamics/Agents.jl/issues/727
    animal_properties = generate_animal_parameters(animal_defs)
    model_properties = Dict(
        :events => events,
        :fully_grown => falses(dims),
        :growth => zeros(Int, dims),
        :regrowth_time => regrowth_time,
        :Δenergy_grass => Δenergy_grass,
    )
    properties = merge(model_properties,animal_properties)
    model = StandardABM(Animal, space; 
        agent_step! = animal_step!, model_step! = model_step!,
        properties, rng, scheduler = Schedulers.Randomly(), warn = false, agents_first = false
    )
    for def in animal_defs
        for _ in 1:def.n
            energy = rand(abmrng(model), 1:(def.Δenergy*2)) - 1
            add_agent!(Animal, model, energy, def, nothing, [], [], [], [])
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
end

# The behavior of grass function differently. If it is fully grown, it is consumable.
# Otherwise, it cannot be consumed until it regrows after a delay specified by
# `regrowth_time`. The dynamics of the grass is our `model_step!` function.
function grass_step!(model)
    ids = collect(allids(model))
    dead_animals = filter(id -> !isnothing(model[id].death_cause), ids)
    for id in ids
        if !isnothing(model[id].death_cause)
            remove_agent!(id, model)
        else
            perceive!(model[id], model)
        end
    end
    @inbounds for p in positions(model) # we don't have to enable bound checking
        if !(model.fully_grown[p...])
            if model.growth[p...] ≥ model.regrowth_time#≤ 0
                model.fully_grown[p...] = true
                #model.growth[p...] = model.regrowth_time
            else
                model.growth[p...] += 1
            end
        end
    end
end

function handle_event!(model)
    ids = collect(allids(model))
    for event in model.events
        if event.timer == event.t_start # start event
            if event.name == "Drought"
                #model.regrowth_time = event.value

                predators = filter(id -> !("Grass" ∈ model[id].def.food), ids)
                for id in predators
                    abmproperties(model)[Symbol(model[id].def.type*"_"*"perception")] = 2
                end
                
            elseif event.name == "Flood"
                model.regrowth_time = event.value
                for id in ids
                    abmproperties(model)[Symbol(model[id].def.type*"_"*"Δenergy")] -= 1
                end
            
            
            elseif event.name == "PreyReproduceSeasonal"
                prey = filter(id -> "Grass" ∈ model[id].def.food, ids)
                for id in prey
                    abmproperties(model)[Symbol(model[id].def.type*"_"*"reproduction_prob")] = event.value
                end
            
            elseif event.name == "PredatorReproduceSeasonal"
                predators = filter(id -> !("Grass" ∈ model[id].def.food), ids)
                for id in predators
                    abmproperties(model)[Symbol(model[id].def.type*"_"*"reproduction_prob")] = event.value
                end

            end
        end

        if (event.timer ≥ event.t_start) && (event.timer < event.t_end)
            if event.name == "Drought"
                for p in positions(model)
                    dry_out_chance = 0.4 * (model.growth[p...] / model.regrowth_time)
                    if model.fully_grown[p...] && (dry_out_chance ≥ rand(abmrng(model))) 
                        #model.growth[p...] = 0
                        model.growth[p...] = rand(abmrng(model), 1:model.regrowth_time) - 1
                        model.fully_grown[p...] = false
                    end
                end
            elseif event.name == "Winter" 
                block_field_every = 2
                i = 1
                for p in positions(model)
                    if i % block_field_every == 0
                        model.growth[p...] = rand(abmrng(model), 1:(model.regrowth_time / 2))
                        model.fully_grown[p...] = false
                    end
                    i += 1
                end
                
            end
        end


        if event.timer == event.t_end # end event
            if event.name == "Drought"
                #model.regrowth_time = event.pre_value
                predators = filter(id -> !("Grass" ∈ model[id].def.food), ids)
                for id in predators
                    abmproperties(model)[Symbol(model[id].def.type*"_"*"perception")] = 1
                end

            elseif event.name == "Flood"
                model.regrowth_time = event.pre_value
                for id in ids
                    abmproperties(model)[Symbol(model[id].def.type*"_"*"Δenergy")] += 1
                end
            
            elseif event.name == "PreyReproduceSeasonal"
                prey = filter(id -> "Grass" ∈ model[id].def.food, ids)
                for id in prey
                    abmproperties(model)[Symbol(model[id].def.type*"_"*"reproduction_prob")] = event.pre_value
                end
            
            elseif event.name == "PredatorReproduceSeasonal"
                predators = filter(id -> !("Grass" ∈ model[id].def.food), ids)
                for id in predators
                    abmproperties(model)[Symbol(model[id].def.type*"_"*"reproduction_prob")] = event.pre_value
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
