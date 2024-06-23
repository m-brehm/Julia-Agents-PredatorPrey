# SCJ-PredatorPrey

SoSe 2024 SCJ Projekt zur Modelierung eines Jäger, Beute Verhältnis in Julia mit Agents.jl

## Verwendung
Um die Anwendung auszuführen, muss Julia installiert sein.

Für die Ausführung sollte ```main.ipynb``` verwendet werden. Damit werden die Abhängigkeiten automatisch installiert und die Anwendung kann interaktiv ausgeführt werden. 

Falls das Ausführen mit ```main.ipynb``` nicht funktioniert, kann auch main.jl verwendet werden.
Jedoch ist in ```main.jl``` nur das zweite Szenario definiert. 

Um die anderen Seznarien zu verwenden, müssen die AnimalDefinitions und Events in ```main.jl``` angepasst werden.

```main.jl``` sollte NICHT über ```julia main.jl``` ausgeführt werden, da sich das interakitve Fenster automatisch schließt.
Das kann verhindert werden, wenn es über eine interaktive shell ausgeführt wird:

```bash
julia
```
```julia
include("main.jl")
```

## Features
**Statistik -** 
Es werden zur Laufzeit des Modells Statistiken zur Population und Todesursache der Agenten bereitgestellt.

**Verschiedene Spezien -**
Es können verschiedene Spezien mit individuellen Paramteren, Fressfeinden und Nahrungsquellen erstellt werden.

**Umweltereignisse -**
Es können vordefinierte Events konfiguriert werden, die die Parameter der Agenten oder des Modells zyklisch anpassen. Folgende Events wurden implementiert.
- Dürre: Grass kann austrocknen und wächst langsamer, Räuber können weiter sehen.
- Flut: Populationen werden schlagartig reduziert.
- Winter: Auf einem gewissen Anteil der Felder wächst kein Gras.
- Saisonale Reproduktion: Anpassung der Reproduktionsraten für Räuber beziehungsweise Beute.

