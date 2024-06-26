import Pkg
Pkg.activate("./env")
using Distributed
@everywhere include("./predator_prey_generic.jl")
using BlackBoxOptim, Random
using Statistics: mean, median
using Serialization
function load(file)
    fh = open(file, "r")
    optctrlb, res = deserialize(fh);
    close(fh)
    return (optctrlb, res)
end 
function generator(x,n)
    models = []
    rng = MersenneTwister(71758)
    for i in 1:n
        animal_defs = [
        #AnimalDefinition(trunc(Int,x[8]),'●',RGBAf(1.0, 1.0, 1.0, 1),x[3], x[3], 1, x[1], x[3], trunc(Int,x[6]), "Sheep", ["Wolf","Bear"], ["Grass"])
        #AnimalDefinition(trunc(Int,x[9]),'▲',RGBAf(0.2, 0.2, 0.3, 1),x[4], x[4], 1, x[2], x[4], trunc(Int,x[7]), "Wolf", [], ["Sheep"])
        AnimalDefinition(trunc(Int,x[6]),'●',RGBAf(1.0, 1.0, 1.0, 1),0, 0, 1, x[1], x[3], 0, "Sheep", ["Wolf","Bear"], ["Grass"])
        AnimalDefinition(trunc(Int,x[7]),'▲',RGBAf(0.2, 0.2, 0.3, 1),0, 0, 1, x[2], x[4], 0, "Wolf", [], ["Sheep"])
        ]
        stable_params = (;
            events = [],
            animal_defs = animal_defs,
            dims = (30, 30),
            regrowth_time = 30,
            Δenergy_grass = x[5],
            #seed = 71758,
        )
        seed = rand(rng,1000:100000)
        push!(models,initialize_model(;seed,stable_params...))
    end
    return models
end
function cost(x)
    steps = 2000
    iterations = 10
    models = generator(x,iterations)
    sheep(a) = a.def.type == "Sheep"
    wolf(a) = a.def.type == "Wolf"
    eaten(a) = a.def.type == "Sheep" && a.death_cause == Predation
    starved(a) = a.def.type == "Sheep" && a.death_cause == Starvation
    count_grass(model) = count(model.fully_grown)
    adata = [(sheep, count), (wolf, count), (eaten, count), (starved, count)]
    mdata = [count_grass]
    df1,df2 = ensemblerun!(models, steps; adata, mdata, parallel=true, showprogress=true)
    println(x)
    fitness_scores = []
    for i in 1:iterations
        df = df1[df1.ensemble .== i,:]
        println(string(count(!iszero,df.count_sheep))*"   "*string(count(!iszero,df.count_wolf)))
        score = count(iszero,df.count_sheep) + 2*count(iszero,df.count_wolf)
        push!(fitness_scores,score)
    end
    fitness = float(sum(fitness_scores))
    println(fitness)
    return fitness
end

#result = bboptimize(cost,SearchRange = [(0.0, 1.0),(0.0, 1.0),(0.0, 30.0),(0.0, 30.0),],NumDimensions = 4,MaxTime = 20,)
SearchRange = [
                (0.01, 0.4),
                (0.01, 0.4),
                (5.0, 30.0),
                (5.0, 30.0),
                (5.0, 30.0),
                #(1, 3),
                #(1, 3),
                (3, 30),
                (3, 30),
            ]
optctrl = bbsetup(cost;SearchRange, MaxTime = 300, Method = :generating_set_search)#, TraceInterval=1.0, TraceMode=:verbose);
#optctrl, res = load("SimpleModellOptimization900.tmp");
res = bboptimize(optctrl)
tempfilename = "./temp" * string(rand(1:Int(1e8))) * ".tmp"
fh = open(tempfilename, "w")
serialize(fh, (optctrl, res))
close(fh)

#cost([0.806586, 0.0481975, 18.5285, 22.329])
#[0.165438, 0.0462449, 15.4501, 12.0382]
#[0.571934, 0.74005, 4.22395, 24.9997, 15.4605, 1.09129, 2.18749, 24.3948, 11.3926]

#Repro_Schaf, Repro_Wolf, Delta_Energie_Schaf, Delta_Energy_Wolf, Delta_Energy_Gras, n_Schaf, n_Wölfe
#[0.26817737483789245, 0.027182763696826588, 14.440470034137558, 27.81279288508929, 15.785601397364756, 28.644469239080397, 13.471462703569484]
#[0.11524114234251756, 0.07378121226251827, 29.31006871020899, 20.47494251025892, 5.915473514486612, 9.568612576389182, 22.299369669891565]

# Schaf stirbt aus obwohl es mehr energy bekommt???
#[0.11524114234251756, 0.07378121226251827, 29.31006871020899, 20.47494251025892, 12.155473514486612, 9.568612576389182, 22.299369669891565]

#Wolf stirbt aus weil Schaf sich zu wenig reproduziert
#[0.016950722103029812, 0.07378121226251827, 29.31006871020899, 20.47494251025892, 5.915473514486612, 9.568612576389182, 22.299369669891565]


#Wolf stirbt aus, da er sich viel zu stark reproduziert
#[0.11524114234251756, 0.25901432860274654, 29.31006871020899, 20.47494251025892, 5.915473514486612, 9.568612576389182, 22.299369669891565]

#Aber hier plötzlich wieder einigermaßen stabil
#[0.11524114234251756, 0.2477989358947258, 29.31006871020899, 20.47494251025892, 5.915473514486612, 9.568612576389182, 22.299369669891565]

#Wolf stirbt weil zu wenig Schafe am Anfang
#[0.11524114234251756, 0.07378121226251827, 29.31006871020899, 20.47494251025892, 5.915473514486612, 3.3286125763891814, 22.299369669891565]

#Einigermaßen stabil, aber Schaf stirbt oft aus, weil zu hohe reproduktion
#[0.39570778081524405, 0.07378121226251827, 29.31006871020899, 20.47494251025892, 5.915473514486612, 9.568612576389182, 22.299369669891565]