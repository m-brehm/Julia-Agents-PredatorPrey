import Pkg
Pkg.activate("./env")
Pkg.instantiate()
include("./predator_prey_generic.jl")

using GLMakie
GLMakie.activate!()
# To view our starting population, we can build an overview plot using [`abmplot`](@ref).
# We define the plotting details for the wolves and sheep:
ashape(a) = a.def.symbol
acolor(a) = a.def.color

# and instruct [`abmplot`](@ref) how to plot grass as a heatmap:
grasscolor(model) = model.growth ./ model.regrowth_time
# and finally define a colormap for the grass:
heatkwargs = (colormap = [:brown, :green], colorrange = (0, 1))

# and put everything together and give it to [`abmplot`](@ref)
return plotkwargs = (;
    agent_color = acolor,
    agent_size = 25,
    agent_marker = ashape,
    agentsplotkwargs = (strokewidth = 1.0, strokecolor = :black),
    heatarray = grasscolor,
    heatkwargs = heatkwargs,
)

events = []
animal_defs = [
AnimalDefinition(30,'●',RGBAf(1.0, 1.0, 1.0, 1),20, 20, 1, 0.3, 20, 3, "Sheep", ["Wolf","Bear"], ["Grass"])
AnimalDefinition(3,'▲',RGBAf(0.2, 0.2, 0.3, 1),20, 20, 1, 0.07, 20, 1, "Wolf", [], ["Sheep"])
]
stable_params = (;
    events = events,
    animal_defs = animal_defs,
    dims = (30, 30),
    regrowth_time = 30,
    Δenergy_grass = 6,
    seed = 71758,
)

# GLMakie Parameters
model_params_ranges = Dict(
    :regrowth_time => 0:1:100,
    :Δenergy_grass => 0:1:50,
)
animal_params_ranges = generate_animal_parameter_ranges(animal_defs)
params = merge(model_params_ranges,animal_params_ranges)

# Data Collection
sheep(a) = a.def.type == "Sheep"
wolf(a) = a.def.type == "Wolf"
eaten(a) = a.def.type == "Sheep" && a.death_cause == Predation
starved(a) = a.def.type == "Sheep" && a.death_cause == Starvation
count_grass(model) = count(model.fully_grown)
adata = [(sheep, count), (wolf, count), (eaten, count), (starved, count)]
mdata = [count_grass]

# initialize and run
model = initialize_model(;stable_params...)
fig, abmobs = abmexploration(
    model;
    params,
    plotkwargs...,
    adata,
    alabels = ["Sheep", "Wolf", "Eaten", "Starved"],
    mdata, mlabels = ["Grass"]
)
display(fig)