# # Predator-prey dynamics

# ```@raw html
# <video width="auto" controls autoplay loop>
# <source src="../sheepwolf.mp4" type="video/mp4">
# </video>
# ```

# The predator-prey model emulates the population dynamics of predator and prey animals who
# live in a common ecosystem and compete over limited resources. This model is an
# agent-based analog to the classic
# [Lotka-Volterra](https://en.wikipedia.org/wiki/Lotka%E2%80%93Volterra_equations)
# differential equation model.

# This example illustrates how to develop models with
# heterogeneous agents (sometimes referred to as a *mixed agent based model*),
# incorporation of a spatial property in the dynamics (represented by a standard
# array, not an agent, as is done in most other ABM frameworks),
# and usage of [`GridSpace`](@ref), which allows multiple agents per grid coordinate.

# ## Model specification
# The environment is a two dimensional grid containing sheep, wolves and grass. In the
# model, wolves eat sheep and sheep eat grass. Their populations will oscillate over time
# if the correct balance of resources is achieved. Without this balance however, a
# population may become extinct. For example, if wolf population becomes too large,
# they will deplete the sheep and subsequently die of starvation.

# We will begin by loading the required packages and defining two subtypes of
# `AbstractAgent`: `Sheep`, `Wolf`. Grass will be a spatial property in the model.  All three agent types have `id` and `pos`
# properties, which is a requirement for all subtypes of `AbstractAgent` when they exist
# upon a `GridSpace`. Sheep and wolves have identical properties, but different behaviors
# as explained below. The property `energy` represents an animals current energy level.
# If the level drops below zero, the agent will die. Sheep and wolves reproduce asexually
# in this model, with a probability given by `reproduction_prob`. The property `Δenergy`
# controls how much energy is acquired after consuming a food source.

# Grass is a replenishing resource that occupies every position in the grid space. Grass can be
# consumed only if it is `fully_grown`. Once the grass has been consumed, it replenishes
# after a delay specified by the property `regrowth_time`. The property `countdown` tracks
# the delay between being consumed and the regrowth time.

# ## Making the model
# First we define the agent types
# (here you can see that it isn't really that much
# of an advantage to have two different agent types. Like in the [Rabbit, Fox, Wolf](@ref)
# example, we could have only one type and one additional filed to separate them.
# Nevertheless, for the sake of example, we will use two different types.)
using Agents, Random
@agent struct Sheep(GridAgent{2})
    energy::Float64
    reproduction_prob::Float64
    Δenergy::Float64
    perception::Int32
    nearby_agents
    nearby_grass
    #speed::Float64
    #endurance::Float64
end
function perceive!(sheep::Sheep,model)
    sheep.nearby_agents = nearby_agents(sheep, model, model.sheep_perception)#sheep.perception)
    sheep.nearby_grass = nearby_fully_grown(sheep, model)
end
function move!(sheep::Sheep,model)
    wolves = filter(x -> isa(x, Wolf), collect(sheep.nearby_agents))
    if !isempty(wolves)
        closest_wolf = findmin(wolf -> sqrt(sum((sheep.pos .- wolf.pos) .^ 2)), wolves)[2]
        move_away!(sheep, wolves[closest_wolf].pos, model)
    elseif !isempty(sheep.nearby_grass)
        pos = random_empty_fully_grown(sheep.nearby_grass, model)
        move_towards!(sheep, pos, model)
    else
        randomwalk!(sheep, model)
    end
    sheep.energy -= 1
end
function eat!(sheep::Sheep, model)
    if model.fully_grown[sheep.pos...]
        sheep.energy += model.Δenergy_sheep#sheep.Δenergy
        model.fully_grown[sheep.pos...] = false
    end
    return
end
function reproduce!(sheep::Sheep, model)
    print(model.sheep_reproduce)
    if rand(abmrng(model)) ≤ model.sheep_reproduce#sheep.reproduction_prob
        sheep.energy /= 2
        replicate!(sheep, model)
    end
end

function Agents.agent2string(agent::Sheep)
    """
    Sheep
    ID = $(agent.id)
    energy = $(agent.energy)
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
function nearby_fully_grown(sheep::Sheep, model)
    nearby_pos = nearby_positions(sheep.pos, model, sheep.perception)
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

@agent struct Wolf(GridAgent{2})
    energy::Float64
    reproduction_prob::Float64
    Δenergy::Float64
    perception::Int32
    nearby_agents
    #speed::Float64
    #endurance::Float64
end
function perceive!(wolf::Wolf,model)
    wolf.nearby_agents = nearby_agents(wolf, model, model.wolf_perception)#wolf.perception)
end
function move!(wolf::Wolf,model)
    sheeps = filter(x -> isa(x, Sheep), collect(wolf.nearby_agents))
    if !isempty(sheeps)
        closest_sheep = findmin(sheep -> sqrt(sum((wolf.pos .- sheep.pos) .^ 2)), sheeps)[2]
        move_towards!(wolf, sheeps[closest_sheep].pos, model; ifempty=false)
    else
        randomwalk!(wolf, model; ifempty=false)
    end
    wolf.energy -= 1
end
function eat!(wolf::Wolf, model)
    dinner = first_sheep_in_position(wolf.pos, model)
    if !isnothing(dinner)
        remove_agent!(dinner, model)
        wolf.energy += model.Δenergy_wolf#wolf.Δenergy
    end
end
function reproduce!(wolf::Wolf, model)
    if rand(abmrng(model)) ≤ model.wolf_reproduce#wolf.reproduction_prob
        wolf.energy /= 2
        replicate!(wolf, model)
    end
end

function Agents.agent2string(agent::Wolf)
    """
    Wolf
    ID = $(agent.id)
    energy = $(agent.energy)
    """
end

function first_sheep_in_position(pos, model)
    ids = ids_in_position(pos, model)
    j = findfirst(id -> model[id] isa Sheep, ids)
    isnothing(j) ? nothing : model[ids[j]]::Sheep
end

# The function `initialize_model` returns a new model containing sheep, wolves, and grass
# using a set of pre-defined values (which can be overwritten). The environment is a two
# dimensional grid space, which enables animals to walk in all
# directions.

function initialize_model(;
        events = [],
        n_sheep = 100,
        n_wolves = 50,
        dims = (20, 20),
        regrowth_time = 30,
        Δenergy_sheep = 4,
        Δenergy_wolf = 20,
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
    properties = Dict(
        :events => events,
        :fully_grown => falses(dims),
        :countdown => zeros(Int, dims),
        :regrowth_time => regrowth_time,
        :Δenergy_sheep => Δenergy_sheep,
        :Δenergy_wolf => Δenergy_wolf,
        :sheep_reproduce => sheep_reproduce,
        :wolf_reproduce => wolf_reproduce,
        :sheep_perception => sheep_perception,
        :wolf_perception => wolf_perception
    )
    model = StandardABM(Union{Sheep, Wolf}, space; 
        agent_step! = sheepwolf_step!, model_step! = custom_model_step!,
        properties, rng, scheduler = Schedulers.Randomly(), warn = false
    )
    
    ## Add agents
    for _ in 1:n_sheep
        energy = rand(abmrng(model), 1:(Δenergy_sheep*2)) - 1
        add_agent!(Sheep, model, energy, sheep_reproduce, Δenergy_sheep, sheep_perception, [], [])
    end
    for _ in 1:n_wolves
        energy = rand(abmrng(model), 1:(Δenergy_wolf*2)) - 1
        add_agent!(Wolf, model, energy, wolf_reproduce, Δenergy_wolf, wolf_perception, [])
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
function sheepwolf_step!(sheep::Sheep, model)
    perceive!(sheep, model)
    move!(sheep, model)
    if sheep.energy < 0
        remove_agent!(sheep, model)
        return
    end
    eat!(sheep, model)
    reproduce!(sheep, model)
end

function sheepwolf_step!(wolf::Wolf, model)
    perceive!(wolf, model)
    move!(wolf, model)
    if wolf.energy < 0
        remove_agent!(wolf, model)
        return
    end
    eat!(wolf, model)
    reproduce!(wolf, model)
end

function custom_model_step!(model)
    event_handler!(model)
    grass_step!(model)
end

# The behavior of grass function differently. If it is fully grown, it is consumable.
# Otherwise, it cannot be consumed until it regrows after a delay specified by
# `regrowth_time`. The dynamics of the grass is our `model_step!` function.
function grass_step!(model)
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
    
    for event in model.events
        if event.timer == event.t_start # start event
            if event.name == "Drought"
                model.regrowth_time = event.value
                model.wolf_perception += 1
                model.sheep_perception += 1

            elseif event.name == "Flood"
                model.regrowth_time = event.value
                model.Δenergy_wolf = model.Δenergy_wolf - 1
                model.Δenergy_sheep = model.Δenergy_sheep - 1
            
            elseif event.name == "PreyReproduceSeasonal"
                model.sheep_reproduce = event.value
            
            elseif event.name == "PredatorReproduceSeasonal"
                model.wolf_reproduce = event.value

            end
        end

        if event.timer == event.t_end # end event
            if event.name == "Drought"
                model.regrowth_time = event.pre_value
                model.wolf_perception -= 1
                model.sheep_perception -= 1

            elseif event.name == "Flood"
                model.regrowth_time = event.pre_value
                model.Δenergy_wolf = model.Δenergy_wolf + 1
                model.Δenergy_sheep = model.Δenergy_sheep + 1
            
            elseif event.name == "PreyReproduceSeasonal"
                model.sheep_reproduce = event.pre_value
            
            elseif event.name == "PredatorReproduceSeasonal"
                model.wolf_reproduce = event.pre_value

            end
        end

        if event.timer == event.t_cycle # reset cycle
            event.timer = 1
        else
            event.timer += 1
        end
    end
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

