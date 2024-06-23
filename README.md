# SCJ-PredatorPrey

SoSe 2024 SCJ Projekt zur Modelierung eines Jäger, Beute Verhältnis in Julia mit Agents.jl

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

