## Chiamata principale

Lo script `main.py` chiama tutti gli altri in successione e tiene traccia dei tempi di esecuzione se chiamato con l'opzione `--verbose`.

E' possibile modificare i nomi di ogni file lavorando con `config/file_names.json`.
E' possibile modificare i parametri di generazione delle istanze con `config/generator.json`.

Si possono passare le flag:
- `--input` per specificare la cartella con dentro le istanze (divise in gruppi). Il default è specificato in `config/file_names.json`
- `--master-method` può essere `asp|milp_basic|milp_optimized|milp_epsilon`
- `--subproblem-method` può essere `asp|milp`
- `--time-limit` ferma master e subproblem dopo x secondi
- `--max-iteration` è il massimo numero di iterazioni sulla singola istanza (default `10`)
- `--use-cores` se utilizzare i cores
- `--expand-core-days` se espanderli su più giorni (oppure utilizzare solo il giorno che ne è la causa)
- `--expand-core-names` se anonimizzare il nome dei pazienti o no
- `--verbose` se stampare a video i tempi di tutte le fasi di esecuzione. A volte ahimè il tempo è falsato dall'overhead richiesto per lo spawn del processo.

## Ciclo di esecuzione

1. chiamare `generate_instances.py`
    - legge `config/generator.json` e `file_names.json` per i parametri di generazione
    - produce tante istanze `mashp_input.json` nella cartella `./instances/` (si può cambiare in `file_names.json`)
    - le istanze sono raggruppate per numero di giorni e poi per numero di pazienti
    - i numeri di giorni e pazienti sono configurabili con un sistema start-stop-step

2. chiamare `compute_subsumptions.py`
    - legge `file_names.json` e poi tutte le istanze una alla volta
    - in ogni cartella di istanza crea `subsumptions.json` con le relazioni di minore-o-uguale fra giorni
    - le relazioni sono separate per ogni care unit

3. chiamare `solve_master.py`
    - legge `file_names.json` e poi tutte le istanze una alla volta
    - se è presente il file `cores.json` (alla prima iterazione non ci sarà) lo legge e aggiunge vincoli
    - per utilizzare i core è necessario fornire la flag `--use-cores`
    - per anonimizzare i pazienti bisogna fornire la flag `--expand-core-names`
    - il metodo di risoluzione è specificabile con `--method asp|milp`
    - verrà creato il file `subproblemInput.json` contenente il tentativo di assegnamento dei pacchetti

4. chiamare `solve_subproblem.py`
    - legge `file_names.json` e poi tutte le istanze una alla volta (serve `mashp_input.json` e `subproblemInput.json`)
    - risolve i sottoproblemi di ogni giorno e scrive `results.json` con gli assegnamenti finali
    - il metodo di risoluzione è specificabile con `--method asp|milp_basic|milp_optimized|milp_epsilon`

5. chiamare `compute_cores.py`
    - legge `file_names.json` e poi tutte le istanze una alla volta (serve `mashp_input.json`, `subproblemInput.json` e `results.json`)
    - crea `cores.json` con un core per ogno pacchetto non soddisfatto dal subproblem
    - se si specifica la flag `--expand-days` verrà letto anche `subsumptions.json` e i core saranno espansi con tutti i giorni più piccoli

6. si ripetono le fasi 3, 4, 5 in successione fino al completo assegnamento di ogni richiesta oppure fino al raggiungimento di una ITERMAX

## Note

- ogni script è diviso in 3 parti: la prima di setting, la seconda con le funzioni e in fondo il main.
- per visualizzare l'elenco di flag e parametri di ogni script utilizzare `-h`
- La cartella `asp_programs` contiene i due file ASP che risolvono master e sottoproblema, li ho scritti velocemente e di sicuro possono essere migliorati
- la risoluzione ASP richiede di creare dei file temporanei `temp.lp` e `temp.txt` nella cartella root del progetto che però sono eliminati subito dopo. **Attenzione a non usare questi nomi per altri file**