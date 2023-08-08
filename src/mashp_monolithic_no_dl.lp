#const not_sched_occ_w=1.
#const not_sched_occ_prior=2.

#const temp_not_sched_w=1.
#const temp_not_sched_prior=2.

#const changed_temp_date_w=1.
#const changed_temp_date_prior=1.

#const tot_trip_w=1.
#const tot_trip_prior=0.

#const max_trip_prior=0.

% DEF
    %%% -- PACKET OCCURRENCE:  it's the instance to be scheduled, and the occurrence value is used for the calculation
    %                           of the ideal date starting from the prescribed start   
occurrence_to_schedule(Pat, ((Prot, Iter, Pkt_in_Prot), Occ)) :- 
    packet_instance(Pat, Prot, Iter, Pkt_in_Prot), n_occurrences(Pat, Prot, Iter, Pkt_in_Prot, N_occ), Occ=1..N_occ.

    %%% -- SERVICE CONTAINED:   useful predicate to simplify notation, determines if a package (instance) contains a certain service
service_in_packet(Pat, (Prot, Iter, Pkt), Srv) :- packet_type(Pat, Prot, Iter, Pkt, Type), service_in_packet(Type, Srv).
service_in_packet(Pat, (Pkt, Occ), Srv) :- service_in_packet(Pat, Pkt, Srv), 
                                           occurrence_to_schedule(Pat, (Pkt, Occ)).

    %%% -- TRIPS:              Days when a patient must go to the hospital for some service,
%                               for the trips I exclude those schedules that fall between the horizon 
%                               as a tolerance that could be made to coincide with others subsequent ones when reviewed
trip(Pat,Day) :- patient(Pat), horizon(Day), schedule(Pat,Pkt,Day), min_max_tolerance(Pat,Pkt,_,Max), horizon(Max).

    %%% -- IDEAL DATE:          This is the date obtained by adding the frequency value to each occurrence 
%                               starting from the package start
ideal_date(Pat, ((Prot, Iter, Pkt), Occ), Day) :- occurrence_to_schedule(Pat, ((Prot, Iter, Pkt), Occ)), packet_frequency(Pat, Prot, Iter, Pkt, Freq), 
                                                   packet_start(Pat, Prot, Iter, Pkt, S), protocol_iteration_start(Pat, Prot, Iter, Inizio_prot),
                                                   Day=Inizio_prot+S-1+Freq*(Occ-1).

    %%% -- TOLERANCE EXTREMES:  Extremes of the tolerance of each occurrence
min_max_tolerance(Pat, ((Prot, Iter, Pkt), Occ), Min, Max) :- occurrence_to_schedule(Pat, ((Prot, Iter, Pkt), Occ)), packet_tolerance(Pat, Prot, Iter, Pkt, Tol),
                                                    ideal_date(Pat, ((Prot, Iter, Pkt), Occ), Ideal_date),
                                                    Min=Ideal_date-Tol, 
                                                    Max=Ideal_date+Tol.

    %%% -- TOLERANCE DAYS:      Collect from the previous the single days candidates for scheduling the occurrence
within_tolerance(Pat, Pkt, (Min..Max)) :- min_max_tolerance(Pat, Pkt, Min, Max).

    %%% -- SCHEDULED SERVICE:
sched_service(Pat, Srv, Day) :- schedule(Pat, Pkt, Day), service_in_packet(Pat, Pkt, Srv).

    %%% -- VARIABILITY:         from the predicate that describes min-max I obtain as for the tolerance a predicate for 
    %                           each day of that interval
variability(Pat, Pkt, Min..Max) :- variability(Pat, Pkt, Min, Max).

    %%% -- SCHEDULED SERVICES:  I extract from the schedule which services are expected on a certain day, regardless of the package
schedule_srv(Day,Pat,Srv) :- schedule(Pat, Pkt, Day), service_in_packet(Pat, Pkt, Srv).


% GENERATE
%%% -- SCHEDULE:    Generate a schedule for each occurrence within the scheduling horizon,
                    % provided that it falls within its tolerance period.
                    % Set the schedule for each occurrence whose ideal date is within the horizon,
                    % otherwise assume that it needs to be scheduled later.
                    % NOTE: with the rolling horizon and the possibility to adjust some schedules,
                    % the last part of the previous window can be revised at the beginning
                    % of the next execution (overlap).
                    % Therefore, I must set the schedule for those schedules labeled as provisional.
0{schedule(Pat, Pkt, Day) : horizon(Day), within_tolerance(Pat, Pkt, Day)}1 :-        
                    occurrence_to_schedule(Pat, Pkt),                     
                    ideal_date(Pat, Pkt, IdealD), horizon(IdealD),    
                    not temp_schedule(Pat, Pkt, _).              
                                                                                                                                                            
%                   Generate a schedule also for provisional schedules derived from
%                   the previous execution.
0{schedule(Pat, Pkt, Day) : horizon(Day),
     variability(Pat, Pkt, Day),
     within_tolerance(Pat, Pkt, Day)}1 :-
     temp_schedule(Pat, Pkt, _).

%### DEBUG #############################################################################################################################################################################################
    %%% -- CAMBIO DATA:         Ogni volta che uno schedule provvisorio viene schedulato in un giorno diverso 
    %                           della sua variability' conteggio una penalita', questo raccoglie i conteggi per un
    %                           print interpretabile, per contare la funzione obiettivo
date_change(Pat, Pkt) :- temp_schedule(Pat, Pkt, Day1), schedule(Pat, Pkt, Day2), Day1!=Day2.
n_date_change(N) :- N=#count{Pat,Pkt : date_change(Pat,Pkt)}.
%#######################################################################################################################################################################################################

%CONSTRAINTS
    %%% Weak constraint to maximize the number of scheduled occurrences in order to respect all integrity constraints.
:~ occurrence_to_schedule(Pat, Pkt), 
    not schedule(Pat, Pkt, _), 
    not temp_schedule(Pat, Pkt, _),
    ideal_date(Pat, Pkt, Day), horizon(Day), %this allows to not consider packets that should be scheduled beyond the horizon
    priority(Pat, W). [1@W,Pat,Pkt]
                                        %PESATO --> %[W@not_sched_occ_prior,Pat,Pkt]
                                      %[not_sched_occ_w@not_sched_occ_prior,Pat,Pkt]

%%% 2a FO: modificare schedule gia' fissato %%% TEMP. DISABILITATO
    %%% evitare il piu' possibile di cancellare prenotazioni preventivate
%:~ temp_schedule(Pat, Pkt, _), 
%    not schedule(Pat, Pkt, _), 
%    priority(Pat, W).            %[temp_not_sched_w@temp_not_sched_prior,Pat,Pkt]
%                                       [W@temp_not_sched_prior,Pat,Pkt]
    %%% EVITARE IL PIU' POSSIBILE DI CAMBIARE IL DAY preventivato
%:~ temp_schedule(Pat, Pkt, Day1), 
%    schedule(Pat, Pkt, Day2), Day1!=Day2. [changed_temp_date_w@changed_temp_date_prior,Pat,Pkt]

%### DEBUG #######################################################################################################################################
    %count the number of unscheduled occurrences
not_scheduled(Pat, Pkt) :- occurrence_to_schedule(Pat, Pkt), 
                            not schedule(Pat, Pkt, _),
                            not temp_schedule(Pat, Pkt, _),
                            ideal_date(Pat, Pkt, Day), horizon(Day).

n_not_scheduled(N) :- N=#count{Pat,Pkt : not_scheduled(Pat,Pkt)}.

n_not_scheduled(Pr, N) :- priority(_,Pr), N=#count{Pat,Pkt : not_scheduled(Pat,Pkt), priority(Pat,Pr)}.

%#################################################################################################################################################

    %%% -- CAPACITY:            for each day, the sum of resource consumption does not exceed the capacity offered on that day
:- horizon(Day), care_unit(Risorsa), 
    #sum{N,Pat,Srv : sched_service(Pat, Srv, Day), 
    service(Srv, Risorsa, N, _)}>Q, 
    capacity(Day, Risorsa, Q).

    %%% -- INCOMPATIBILITY:     the distance between 2 schedules of the same patient for packages
    %                           that involve incompatible services is greater than the interdiction tau
:-  sched_service(Pat, Srv1, Day1), 
    sched_service(Pat, Srv2, Day2),
    interdiction(Srv1, Srv2, Tau), 
    Day2 - Day1>=0, Tau>0, 
    Day2 <= Day1+Tau. %notare >0 senza = 
                      % se A incomp B, ma non B,A, ammetto che possano 
                      % essere lo stesso giorno, ma dovranno essere in ordine B,A
%:- schedule(Pat, (Pkt_ID1, Occ1), Day), schedule(Pat, (Pkt_ID2, Occ2), Day),
%    service_in_packet(Pat, Pkt_ID1, Srv1), service_in_packet(Pat, Pkt_ID2, Srv2),
%    interdiction(Srv1, Srv2, Tau), interdiction(Srv2, Srv1, Tau), Tau>0. %notare Day=Day 
                                                            % se A incomp B, e anche B incomp A, non ammetto che possano 
                                                            % essere lo stesso giorno

    %%% -- NECESSITY:           the distance between 2 schedules of the same patient for packages
%                               that involve necessary consecutive services is respected
%                               and the second one falls within the correct time window --> take into account 0!
satisfied_necessity(Pat, Pkt1, Srv1, Srv2) :-                        %%%NOTE: DOES NOT STATE THAT IT HAS COUNTERPARTS FOR ALL THE NECESSITIES OF A SERVICE!
                                service_in_packet(Pat, Pkt1, Srv1),
                                service_in_packet(Pat, Pkt2, Srv2),
                                necessity(Srv1, Srv2, (Tau_min, Tau_max)),
                                schedule(Pat, Pkt1, Day1),
                                schedule(Pat, Pkt2, Day2), 
                                Day2 >= Day1+Tau_min, 
                                Day2 <= Day1+Tau_max.

%                               When the packet is at the end of the time horizon, it could be that the necessary packet
%                               is scheduled beyond the horizon, so I'm satisfied
necessity_beyond_horizon(Pat, Pkt1, Srv1, Srv2) :- 
                                occurrence_to_schedule(Pat, Pkt1), 
                                service_in_packet(Pat, Pkt1, Srv1),
                                necessity(Srv1, Srv2, (Tau_min, Tau_max)), schedule(Pat, Pkt1, Day1),
                                Day1+Tau_max>nh, not satisfied_necessity(Pat, Pkt1, Srv1, Srv2).

%                               There cannot be a packet whose necessity is not satisfied
%                               or that cannot be satisfied by a packet outside the horizon
:- schedule(Pat, Pkt1, Day1), 
    service_in_packet(Pat, Pkt1, Srv1),
    necessity(Srv1, Srv2, _), 
    not satisfied_necessity(Pat, Pkt1, Srv1, Srv2), 
    not necessity_beyond_horizon(Pat, Pkt1, Srv1, Srv2).

%                               WITHIN THE Tau_min NO OCCURRENCE OF THAT PACKET SHOULD BE PRESENT
:-  sched_service(Pat, Srv1, Day1), 
    sched_service(Pat, Srv2, Day2),
    necessity(Srv1, Srv2, (Tau_min, _)), 
    Day2 - Day1>=0, 
    Day2 < Day1+Tau_min.

    %%% -- impedisco che ci siano pazienti non serviti
%:- n_pat_trips(_, 0).

% DEF:                        
    %%% -- NUMBER OF TRIPS PER PATIENT
n_pat_trips(Pat,NV) :- patient(Pat), NV = #count{Day : trip(Pat,Day)}.

%                               calculate the maximum number of trips
max_trips(M) :- M = #max{NV : n_pat_trips(_,NV)}, M!=#inf.


%### DEBUG #######################################################################################################################################
    %%% -- CONTEGGIO NECESSITA' NON SODDISFATTE: si intende necessita' non soddisfatte perché al termine dell'orizzonte
%n_nec_non_sodd_paz(Pat,Nn) :- patient(Pat), Nn = #count{1,Prot, Iter, Pkt, Occ, PrA, PrB : necessity_beyond_horizon(Pat, Prot, Iter, Pkt, Occ, PrA, PrB)}.
%tot_nec_non_sodd(Tot) :- Tot = #sum{Nn,Pat : n_nec_non_sodd_paz(Pat,Nn)}.
%#################################################################################################################################################

    %%% FUNZIONE OBIETTIVO:     tenendo conto dei diversi vincoli weak, con priorita' diverse
    %                           l'ultima serve a minimizzare il numero totale degli accessi all'ospedale
%:~trip(Pat,Day).  [tot_trip_w@tot_trip_prior,Pat,Day]

% FO 3: minimizzare il massimo numero di accessi all'ospedale --> temporaneamente disabilitata
%#minimize {Max@max_trip_prior : max_trips(Max)}.


%                                forbidden/fixed date assignments:
%                                In general, regardless of the setting, if I pass not_schedulable/fix_schedule facts
%                                I have to forbid/fix the schedule of those packages. Do not fix A that requires B if B is not
:- schedule(Pat, Pkt, _),   not_schedulable(Pat, Pkt).            %split_pat
:- schedule(Pat, Pkt, Day), not_schedulable(Pat, Pkt, Day).       %greedy
:- not schedule(Pat, Pkt, Day), fix_schedule(Pat, Pkt, Day), 
   necessity_tot_satisfied_fix(Pat, Pkt).                         %both split_pat and greedy
                                                               
    %%% -- GUARANTEED NECESSITY: in the case of greedy, it is guaranteed only if the requested service has already been 
    %                            fixed in the previous iteration
    %                            This says which service satisfies the necessity and which one is fixed
satisfied_necessity_fix_aux(Pat, Pkt1, Srv1, Pkt2, Srv2) :- 
                                schedule(Pat, Pkt1, Day1),
                                schedule(Pat, Pkt2, Day2),
                                fix_schedule(Pat, Pkt2, Day2),
                                service_in_packet(Pat, Pkt1, Srv1),
                                service_in_packet(Pat, Pkt2, Srv2),
                                necessity(Srv1, Srv2, (Tau_min, Tau_max)),  
                                Day2 >= Day1+Tau_min, 
                                Day2 <= Day1+Tau_max.

% A necessity is satisfied if a service that satisfies it is fixed and has no further necessities in the chain
satisfied_necessity_fix(Pat, Pkt1, Srv1, Srv2) :-
                                satisfied_necessity_fix_aux(Pat, Pkt1, Srv1, Pkt2, Srv2),
                                not necessity(Srv2, _, _).

% A necessity is also satisfied if it can be satisfied beyond the horizon
satisfied_necessity_fix(Pat, Pkt1, Srv1, Srv2) :-
                                necessity_beyond_horizon(Pat, Pkt1, Srv1, Srv2).

% Recursively, satisfies the necessity if the required packages satisfy their necessities
satisfied_necessity_fix(Pat, Pkt1, Srv1, Srv2) :- 
                                satisfied_necessity_fix_aux(Pat, Pkt1, Srv1, Pkt2, Srv2),
                                necessity(Srv2, _SrvC, _),
                                necessity_tot_satisfied_fix(Pat, Pkt2).

% A package satisfies all its necessities if all its services satisfy the necessities
necessity_tot_satisfied_fix(Pat, Pkt) :- schedule(Pat, Pkt, _),
    satisfied_necessity_fix(Pat, Pkt, Srv1, Srv2) : service_in_packet(Pat, Pkt, Srv1), 
                                                              necessity(Srv1, Srv2, _).
%FOUNDAMENTAL:
#show schedule/3.
#show not_scheduled/2.
#show necessity_tot_satisfied_fix/2.
%READABILITY OF SOL:
#show max_trips/1.
#show n_not_scheduled/1.
#show n_not_scheduled/2.
#show n_date_change/1.
#show n_pat_trips/2.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%% SP part %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%DEF
    %%% -- CONTIENE PRESTAZIONE:    predicato utile per alleggerire la notazione, determina se un pacchetto (istanza) 
    %                               contiene una certa prestazione
contains_service(Pat, (Prot, It, Pkt), Srv) :- packet_type(Pat, Prot, It, Pkt, Type), service_in_packet(Type, Srv).

    %%% -- service is the basic element to be assigned to a time slot
service(Pat, Srv, Day) :- schedule(Pat, (Pkt_ID, _), Day), contains_service(Pat, Pkt_ID, Srv), horizon(Day).

%%%%%% -- Shifted start of a care unit: create a fake service that precedes all the others assigned to that care unit
service(Res, CU, Day) :- capacity(Day, Res, CU, Start, _), Start>0.                                %Create
service(CU, Res, Day, Dur, 0)    :- service(Res, CU, Day), capacity(Day, Res, CU, Dur, _).         %Assign a Duration = Start
provides(Res, CU, Res, CU, Day)  :- service(Res, CU, Day), capacity(Day, Res, CU, _, _).           %Force the assignment of that CU 
start_time(Res, CU, Day, 0)      :- service(Res, CU, Day), capacity(Day, Res, CU, _, _).

time(0..Tmax) :- Tmax=#max{T : T=S+D, capacity(_,_,_,S,D)}.

%GENERATE
    %%% -- With more than one units of the same kind the SP must decide to which the service has to be assigned
    %       The assigned CU must be of the same type and unique.
1{provides(Res, CU, Pat, Srv, Day) : capacity(_, Res, CU, _, _)}1 :- service(Pat, Srv, Day). %%%% perché non va con service(Srv, Res, _, _) dentro?
:- provides(Res, CU, Pat, Srv, _), not service(Srv, Res, _, _), Pat!=Res, Srv!=CU.               %%%%
:- provides(Res, CU, _, _, Day), not capacity(Day, Res, CU, _, _).

1{start_time(Pat, Srv, Day, Start) : time(Start)}1 :- service(Pat, Srv, Day).

%DEF
    %%% -- Precedes: A service precedes the other if the end of the former is not after the start of the latter
precedes(P1, S1, Day, P2, S2, Day) :- start_time(P1, S1, Day, Start1), start_time(P2, S2, Day, Start2), 
                                service(S1, _, D1, _), not care_unit(P1), not capacity(_,P1,S1,_,_), %vale così se non è il delay fake
                                Start1 + D1 <= Start2.
precedes(Res, CU, Day, P, S, Day) :- start_time(Res, CU, Day, Start1), start_time(P, S, Day, Start2), 
                                service(CU, Res, Day, D1, _), %anche per la service speciale fake
                                Start1 + D1 <= Start2.


%Constraints
    %%% -- different services of the same patient cannot be deployed at the same time, 
    %      one precedes the other
:- not precedes(Pat, Srv1, Day, Pat, Srv2, Day), not precedes(Pat, Srv2, Day, Pat, Srv1, Day), Srv1!=Srv2, 
   service(Pat, Srv1, Day), service(Pat, Srv2, Day), not care_unit(Pat), not capacity(_,Pat,Srv1,_,_), not capacity(_,Pat,Srv2,_,_).
    %non vale per il nome della Risorsa per il delay! e.g. red,1 e red,2 NON SI PRECEDONO

    %%% NOTE: can be changed! --    The same Unit (machine) is in use for only one 
    %                               service of a patient, not for + services or pats 
    %                               at the same time    
    %%% case of >1 Units
:- not precedes(Pat1, Srv1, Day, Pat2, Srv2, Day), not precedes(Pat2, Srv2, Day, Pat1, Srv1, Day), 
   service(Srv1, Res, _, _), service(Srv2, Res, _, _),
   provides(Res, CU, Pat1, Srv1, Day), provides(Res, CU, Pat2, Srv2, Day), 
   Pat1!=Pat2, service(Pat1, Srv1, Day), service(Pat2, Srv2, Day).

:- not precedes(Pat1, Srv1, Day, Pat2, Srv2, Day), not precedes(Pat2, Srv2, Day, Pat1, Srv1, Day), 
   service(Srv1, Res, Day, _, _), service(Srv2, Res, _, _),  %serve adattato per la service fake del delay
   provides(Res, CU, Pat1, Srv1, Day), provides(Res, CU, Pat2, Srv2, Day), 
   Pat1!=Pat2, service(Pat1, Srv1, Day), service(Pat2, Srv2, Day).

:- not precedes(Pat1, Srv1, Day,  Pat2, Srv2, Day), not precedes(Pat2, Srv2, Day,  Pat1, Srv1, Day), 
   service(Srv1, Res, _, _), service(Srv2, Res, _, _), 
   provides(Res, CU, Pat1, Srv1, Day), provides(Res, CU, Pat2, Srv2, Day), 
   Srv1!=Srv2, service(Pat1, Srv1, Day), service(Pat2, Srv2, Day).

:- not precedes(Pat1, Srv1, Day,  Pat2, Srv2, Day), not precedes(Pat2, Srv2, Day,  Pat1, Srv1, Day), 
   service(Srv1, Res, Day, _, _), service(Srv2, Res, _, _), 
   provides(Res, CU, Pat1, Srv1, Day), provides(Res, CU, Pat2, Srv2, Day), 
   Srv1!=Srv2, service(Pat1, Srv1, Day), service(Pat2, Srv2, Day).

    %%% -- Irreflexivity
:- precedes(Pat1, Srv1, Day, Pat1, Srv1, Day).

    %%% -- Antisimmetry
:- precedes(Pat1, Srv1, Day, Pat1, Srv2, Day), 
   precedes(Pat2, Srv2, Day, Pat1, Srv1, Day).

    %%% -- Transitivity
:- precedes(Pat1, Srv1, Day, Pat2, Srv2, Day), 
   precedes(Pat2, Srv2, Day, Pat3, Srv3, Day), 
   not precedes(Pat1, Srv1, Day, Pat3, Srv3, Day).

    %%% -- CAPACITY CONSTRAINT: (Strengthened) --> The sum of the durations of services that precede a service S 
%                                                over a chain, plus the duration of S, cannot exceed capacity
%					                             allocated for that care unit U associated to S

:- service(P,S,Day), 
    service(S,Res,D,_), %non c'é bisogno per la speciale fake
    provides(Res,CU,P,S,Day), 
    start_time(P,S,Day,T),
    capacity(Day, Res, CU, Delay, Q),
    T+D > Delay+Q.

#show start_time/4.
#show service/3.
%#show precedes/6.
#show provides/5.


#script (python)

import glob
from clingo import Number, String, Function, parse_term
import subprocess
import os
import sys
import re
import json
from datetime import datetime

THIS_DIR_tmp  =   '/home/marco/Universita/Dottorato/Studi/Progetto NCDs Agenda/Tesi Vancini/Final'
THIS_DIR_name =   'src'#THIS_DIR_tmp.split('<')[1]
THIS_DIR      =   os.path.join(THIS_DIR_tmp.split('<')[0], THIS_DIR_name)
PARENT_DIR    =   os.path.abspath(os.path.join(THIS_DIR, '..'))
TARGET_DIR    =   os.path.join(PARENT_DIR, 'target')
#print(os.path.dirname(os.path.realpath(sys.argv[0])))  #subprocess con pipe per ritornare lettura

sys.path.append(THIS_DIR)

split_pat_file_fix_sol = os.path.join(TARGET_DIR, 'fixed_sol.lp')

from mashp_tools import read_ASP, get_cur_dir, str_format_times_dict, get_result_values
from collect4cut import collect_info


def breakpoint():
    go=False
    while not go or go=='':
        with open("pass.txt") as p:
            go=p.read()
    with open("pass.txt", 'w') as p:
        p.write('')


def main_monolitico(prg):

    #%###################################################
    #%                 Master Problem                   #
    #%###################################################

    #%prendo il tempo di start della prima iterazione MP  
    nowM_start = datetime.now()
    #%current_time = nowM_start.strftime("%H:%M:%S")
    #%print("\n\nStart Time M1 =", current_time)

    #%avvio grounding e solving del problema com'e' in origine
    prg.ground([("base", [])])
    
    nowM_gr_stop = datetime.now()
    
    prg.solve()

    nowM_stop = datetime.now()
    #%current_time = nowM_stop.strftime("%H:%M:%S")
    #%print("Stop Time M1  =", current_time)

    #%al termine devo scrivere la soluzione nel file 'readable_sol.lp'
    #%e lo faccio con l'apposito script 
    cmd=['python', os.path.join(PARENT_DIR, 'format_master_plan.py')]
    process = subprocess.Popen(cmd)
    process.wait()

    with open(os.path.join(TARGET_DIR, 'time_info.json'), 'w') as time_info_file:
        json.dump({"Grounding Time" : str(nowM_gr_stop - nowM_start),
                   "Solving Time"   : str(nowM_stop    - nowM_gr_stop)}, time_info_file, indent=4)

    print("Durata = "+str(nowM_stop - nowM_start))


def main_iterativo(prg, settings):
    #%Getting horizon dimension from input file
    input_file=os.path.join(PARENT_DIR, "input", "mashp_input.lp")
    l_input = read_ASP(input_file)
    nh = None
    for f in l_input:
        #%find the horizon constant
        if 'nh=' in f:
            horizon_l=re.split('\=|\.', f)
            nh=int(horizon_l[-2])
            break

    #%print('\n*** nh = '+str(nh)+' ***\n')

    #%###################################################
    #%                 Master Problem                   #
    #%###################################################
    
    #%dizionari dei timestamp e dei risultati per controllare i tempi di solving
    timestamp_dict={}
    info_iter_sol_dict={}
    #%prendo il tempo di start della prima iterazione MP  
    nowM_start = datetime.now()
    #current_time = nowM_start.strftime("%H:%M:%S")
    #print("\n\nStart Time M1 =", current_time)

    solve_result=None
#IF multishot...
    if settings['model']=='multishot':

        tl_init=settings["first_iter_tl"]
        tl_incr=settings["iter_tl_incr"]

        #%avvio grounding e solving del problema com'e' in origine
        prg.ground([("base", [])])
        nowM_gr_stop = datetime.now()
        #prg.solve()
        with prg.solve(async_ = True, yield_ = False) as handle:
            optim = handle.wait(tl_init)
            #print(optim)
            if optim:
                print("OPTIMUM REACHED")
            else:
                print("NOT PROVEN OPTIMALITY")
    ##    solve_result=handle.get()
        nowM_stop = datetime.now()
        #current_time = nowM_stop.strftime("%H:%M:%S")
        #print("Stop Time M1  =", current_time)

#ELSE IF no_multishot...
    elif settings['model']=='no_multishot':
        #%avvio grounding e solving del problema com'e' in origine
        prg.ground([("base", [])])
        nowM_gr_stop = datetime.now()
        #%prg.solve()
        time_limit=0
        with open(os.path.join(THIS_DIR, "time_limit.json")) as tl_file:
            tl_d=json.load(tl_file)
            tl=int(tl_d["tl"])
        with prg.solve(async_ = True, yield_ = False) as handle:        
            optim = handle.wait(tl)
            if optim:
                print("OPTIMUM REACHED")
            else:
                print("NOT PROVEN OPTIMALITY")
    ###        solve_result=handle.get()
        nowM_stop = datetime.now()
        #current_time = nowM_stop.strftime("%H:%M:%S")
        #print("Stop Time M1  =", current_time)
	    
#END IF ELSE
	    
    #%al termine devo scrivere la soluzione nel file 'readable_sol.lp'
    #%e lo faccio con l'apposito script 
    cmd=['python', os.path.join(PARENT_DIR, 'format_master_plan.py')]
    process = subprocess.Popen(cmd)
    process.wait()


    #%###################################################
    #%                   Sub Problem                    #
    #%###################################################
    #%Nota che agisce anche se il Master e' diventato UNSAT.
    #%In questo modo aggiorno tutte le soluzioni giornaliere (che fa terminare il loop)
    #%MA potrebbe essere rimosso e fatto agire solo per sol. SAT.

#%IF multishot...
    #if settings['model']=='multishot':
        #%prendo il tempo di inizio di tutti i SP
    nowS_start = datetime.now()
        #current_time = nowS_start.strftime("%H:%M:%S")
        #print("Start Time S1 =", current_time)
#%END IF multishot

    #%terminato il solving devo avviare tutti i SP per ciascun giorno (nh)
    p_list=[]
    output_file_l=[]
    for i in range(1, nh+1):
        output_file=open(os.path.join(TARGET_DIR, 'daily_agenda{}.lp'.format(i)), 'w')
        output_file_l.append(output_file)
        if settings['sp_dl'] == 'yes':
            cmd = ['clingo-dl', '-c', 'day='+str(i), input_file, os.path.join(TARGET_DIR, 'readable_sol.lp'), os.path.join(THIS_DIR, 'mashp_daily_scheduler.lp')]
        else:
            cmd = ['clingo', '-c', 'day='+str(i), input_file, os.path.join(TARGET_DIR, 'readable_sol.lp'), os.path.join(THIS_DIR, 'mashp_daily_scheduler_no_dl.lp')]
        if settings['sp_obj'] == 'opt':
            cmd.append(os.path.join(THIS_DIR, 'mashp_daily_scheduler_obj_func.lp'))
        elif settings['sp_obj'] == 'sat':
            cmd.append(os.path.join(THIS_DIR, 'mashp_daily_scheduler_sat_constr.lp'))
        if settings['nogood'] == 'greedy': #solo nel caso greedy, non puo' rifiutare cose che ho assegnato all'iterazione percedente
            cmd.append(os.path.join(TARGET_DIR, 'nogood.lp'))
        if settings['split_patients'] == 'yes':
            if os.path.isfile(split_pat_file_fix_sol):
                cmd.append(split_pat_file_fix_sol)
        process = subprocess.Popen(cmd, stdout=output_file, stderr=output_file)
        if settings['parallelize_sp'] == 'no':
            process.wait()
        else:
            p_list.append(process)
    for process in p_list:
        process.wait()
    for output_file in output_file_l:
        output_file.close()

    #%prendo il tempo di terminazione di tutti i SP
    nowS_stop = datetime.now()
    #current_time = nowS_stop.strftime("%H:%M:%S")
    #print("Stop Time S1  =", current_time)

    iter_counter=1
    #%dopo la prima iterazione inserisco i tempi salvati nel dizionario apposito
    timestamp_dict[iter_counter]={'M_tot'      :    (nowM_start, nowM_stop), 
                                  'M_grounding':    (nowM_start, nowM_gr_stop),
                                  'M_solving'  :    (nowM_gr_stop, nowM_stop),
                                  'S_tot'      :    (nowS_start, nowS_stop)
                                  }

#%IF multishot...
    if settings['model']=='multishot':

        #salvo le info dei risultati della prima iterazione      
        search_file = glob.glob(os.path.join(TARGET_DIR, 'daily_agenda*.lp'))
        search_file = [f for f in search_file if not re.search('_p.\.lp', f)]
        #salvo la sol del master
        info_dict={'mp' : get_result_values(os.path.join(TARGET_DIR, 'sol.lp'))}
        #salvo le sol dei SP
        for fsp in search_file:
            info_dict['sp{}'.format(fsp.split('daily_agenda')[-1].split('.lp')[0])] = get_result_values(fsp)
        info_iter_sol_dict[iter_counter]=info_dict
        with open(os.path.join(TARGET_DIR, 'sol_info.json'), 'w') as sol_info_file: #lo faccio ad ogni iteraz. cosi' si puo' monitorare, ma posso farlo al termine
            json.dump(info_iter_sol_dict, sol_info_file, indent=4)

        #%########################################################################
        #%QUESTA VA TOLTA MI RACCOMANDO, e' SOLO PER PROVARE
        #%with open(os.path.join(TARGET_DIR, 'daily_agenda1.lp'), 'w') as cambio:
        #%    cambio.write('UNSATISFIABLE')
        #%#########################################################################

        #%Flag per evitare loop in caso sia insoddisfacibile già il MP all'inizio
        #%UNSAT=False
        #%with open(os.path.join(TARGET_DIR, 'readable_sol.lp'), 'r') as s_file:
        #%    line=s_file.readline()
        #%    while(line):
        #%        if 'UNSATISFIABLE' in line:
        #%            UNSAT=True
        #%            break
        #%        line=s_file.readline()    

        #%a questo punto devo raccogliere le info degli SP per generare i cut da aggiungere al MP
        cut_d = collect_info()
        #print('\n'+str(cut_d)+'\n')

        greedy_fixed=[] #per evitare di ripetere valori fissati gia' in precedenza
        #%finche' esistono agende giornaliere non ammissibili, itero aggiungendo clausole di no-good
        while cut_d: #% and not UNSAT:

            #%%%%%%%%%%%%
            #breakpoint() #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
            #%%%%%%%%%%%%

            #%###################################################
            #%                 Master Problem                   #
            #%###################################################

            #%catturo il timestamp dell'inizio della seconda iterazione
            nowM_start = datetime.now()
            #current_time = nowM_start.strftime("%H:%M:%S")
            #print("Start Time M{} =".format(str(iter_counter)), current_time)

            #%check if timeout is reached
            if os.path.exists(os.path.join(PARENT_DIR, 'test', 'tmp_time_limit.json')):
                with open(os.path.join(PARENT_DIR, 'test', 'tmp_time_limit.json'), 'r') as tmp_tl_file:
                    tmp_tl_d=json.load(tmp_tl_file)

    # DEBUG #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%            
    #            with open(os.path.join(PARENT_DIR, 'debug.txt'), 'a+') as dbg:
    #                dbg.write(datetime.strftime(datetime.strptime(tmp_tl_d['end'], '%y-%m-%d %H:%M:%S'), '%y-%m-%d %H:%M:%S'))
    #                dbg.write('\t')
    #                dbg.write(datetime.strftime(nowM_start, '%y-%m-%d %H:%M:%S'))
    #                dbg.write('\n')
    #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
                
                if datetime.strptime(tmp_tl_d['end'], '%y-%m-%d %H:%M:%S')<=nowM_start:
                    break

            #%devo creare una lista di elementi da rendere ground all'interno del programma nogood
            #%che contiene le informazioni raccolte sul nogood da inserire, i.e. ogni termine della
            #%nuova clausola 
            add_ground=[]

            #MODELLO GREEDY
            if settings['nogood'] == 'greedy':
                with open(os.path.join(TARGET_DIR, 'nogood.lp'), 'a') as ng:
                    if iter_counter == 1: ng.write('greedy.\n')
                    index_printed=False
                    for day,l in cut_d.items():
                        #print("fisso soluzioni della data"+' '+str(day)+' '+str(l))
                        for t in l['sat']:
                            if not t in greedy_fixed:
                                add_ground.append(("greedy", [parse_term('sat'),parse_term(t[0]), parse_term(t[1]), Number(int(t[2])), Number(int(t[3])), Number(int(t[4])), Number(int(t[5]))]))
                                greedy_fixed.append(t)
                                if not index_printed:
                                    ng.write(f"%Iter: {iter_counter}\n")
                                    index_printed=True
                                ng.write("fix_schedule({},{},{},{},{},{}).\n".format(t[0], t[1], t[2], t[3], t[4], t[5]))
                        for t in l['unsat']:
                            add_ground.append(("greedy", [parse_term('unsat'),parse_term(t[0]), parse_term(t[1]), Number(int(t[2])), Number(int(t[3])), Number(int(t[4])), Number(int(t[5]))]))
                            if not index_printed:
                                ng.write(f"%Iter: {iter_counter}\n")
                                index_printed=True
                            ng.write("not_schedulable({},(({},{},{}),{}),{}).\n".format(t[0], t[1], t[2], t[3], t[4], t[5]))


            #%VERSIONE NAIVE
            if settings['nogood'] == 'naive':
                for day,l in cut_d.items():
                    print("aggiungo vincolo della data"+' '+str(day))#%+' '+str(l))
                    for t in l:
                        add_ground.append(("nogood", [parse_term(t[0]), parse_term(t[1]), Number(int(t[2])), Number(int(t[3])), Number(int(t[4])), Number(int(t[5])), Number(iter_counter)]))
                        #%qui sto usando iter_counter come ID del gruppo di pazienti, potrebbe essere necessario diverso
                        #%qualora si trovassero piu' gruppi alla stessa iterazione


            #%VERSIONE UNSAT CORES singolo giorno (BASIC)
            elif settings['nogood'] == 'basic_unsat_core':
                gid=0
                for day,l in cut_d.items():
                    for grp in l:
                        print("aggiungo vincolo della data"+' '+str(day))#%+' '+str(grp))
                        for t in grp:
                            add_ground.append(("nogood_cut", [parse_term(t[0]), parse_term(t[1]), Number(int(t[2])), Number(int(t[3])), Number(int(day)), Number(iter_counter), Number(gid)]))
                        gid+=1
            

            #%VERSIONE UNSAT CORES RIDOTTI singolo giorno [multipacchetti con nome] (NAIVE)   -- usa cut_d dei multipacket
            elif settings['nogood'] == 'multipacket_with_names1':
                for day,gd in cut_d.items():
                    for gid, mpkt_d in gd.items():
                        print("aggiungo vincolo della data"+' '+str(day))#%+' '+str(gid))
                        for mpkt_id,pat_name in enumerate(mpkt_d):
                            mpkt_label = '_'.join(sorted(mpkt_d[pat_name]))
                            for srv in mpkt_d[pat_name]:
                                #print([pat_name, mpkt_label, srv, int(day), iter_counter, gid])
                                add_ground.append(("multipacket_nogood_with_names", [parse_term(pat_name), parse_term(mpkt_label), parse_term(srv), Number(int(day)), Number(int(iter_counter)), Number(int(gid))]))        


            #%VERSIONE UNSAT CORES COMBINAZIONE TUTTI I NOMI
            elif settings['nogood'] == 'multipacket_with_names2':
                for day,group_d in cut_d.items():
                    for gid, group_l in group_d.items():
                        for mpkt_id,mpkt in enumerate(group_l):
                            mpkt_label='_'.join(sorted(mpkt[1]))
                            for srv in mpkt[1]:
                                add_ground.append(("multipacket_nogood_with_names", [parse_term(mpkt[0]), 
                                                                                    parse_term(mpkt_label), 
                                                                                    #%int(mpkt_id), 
                                                                                    parse_term(srv), 
                                                                                    Number(int(day)), 
                                                                                    iter_counter, gid]))

            #%VERSIONE UNSAT CORES MULTIPACKETS : INSERIMENTO CORRETTO MA NON FUNZIONA ASP
            elif settings['nogood'] == 'multipacket_unsat_core':
                for day,gd in cut_d.items():
                    for gid, mpkt_d in gd.items():
                        print("aggiungo vincolo della data"+' '+str(day))#%+' '+str(gid))
                        for mpkt_id,pat_name in enumerate(mpkt_d):
                            mpkt_label = '_'.join(sorted(mpkt_d[pat_name]))
                            for srv in mpkt_d[pat_name]:
                                #print([pat_name, mpkt_label, mpkt_id, srv, int(day), iter_counter, gid])
                                add_ground.append(("multipacket_nogood", [parse_term(mpkt_label), Number(int(mpkt_id)), parse_term(srv), Number(int(day)), Number(iter_counter), Number(gid)]))        
            
            print("ITER COUNTER = ",iter_counter)
            #%aggiungo gli elementi al programma
            #%e.g.
            #%prg.ground([("nogood", [parse_term("joeanthony"),parse_term("pi74"),3,1,3,132,4]),  %[paz, prot, iter, pacc, occ, giorno, gid]
            #%           ("nogood", [parse_term("gaelan"),parse_term("pi529"), 2,1,1,132,3])])
            
            #%if iter_counter>1:
            #%    prg.release_external(Function("q", [iter_counter-1]))
            #%prg.cleanup()
            nowM_gr_start = datetime.now()
            nowM_gr_stop = nowM_gr_start
            if add_ground:
            #%    prg.assign_external(Function("q", [iter_counter]), True)
                prg.ground(add_ground)
                #prg.ground([("base",[])])
                nowM_gr_stop = datetime.now()
            # prg.solve() #%no timeout
                try:
                    with prg.solve(async_ = True, yield_ = False) as handle:
                        optim = handle.wait(tl_init + tl_incr*iter_counter)
                        #print(optim)
                        if optim:
                            print("OPTIMUM REACHED")
                        else:
                            print("NOT PROVEN OPTIMALITY")
            ##            solve_result=handle.get()
                except:
                    print("terminazione")
            iter_counter+=1

            #%catturo il tempo di termine della seconda iterazione
            nowM_stop = datetime.now()
            #current_time = nowM_stop.strftime("%H:%M:%S")
            #print("Stop Time M{}  =".format(iter_counter), current_time)

            #%creo il file readable_sol.lp
            cmd=['python', os.path.join(PARENT_DIR, 'format_master_plan.py')]
            process = subprocess.Popen(cmd)
            process.wait()


            #%###################################################
            #%                    Sub Problem                   #
            #%###################################################
            #%Nota che agisce anche se il Master e' diventato UNSAT.
            #%In questo modo aggiorno tutte le soluzioni giornaliere (che fa terminare il loop)
            #%MA potrebbe essere rimosso e fatto agire solo per sol. SAT.

            #%catturo il timestamp dell'inizio della seconda iterazione
            nowS_start = datetime.now()
            #%current_time = nowS_start.strftime("%H:%M:%S")
            #%print("Start Time S{} =".format(iter_counter), current_time)

            #%terminato il solving devo avviare tutti i SP per ciascun giorno (nh)
            p_list=[]
            output_file_l=[]
            for i in range(1, nh+1):
                output_file=open(os.path.join(TARGET_DIR, 'daily_agenda{}.lp'.format(i)), 'w')
                output_file_l.append(output_file)
                if settings['sp_dl'] == 'yes':
                    cmd = ['clingo-dl', '-c', 'day='+str(i), input_file, os.path.join(TARGET_DIR, 'readable_sol.lp'), os.path.join(THIS_DIR, 'mashp_daily_scheduler.lp')]
                else:
                    cmd = ['clingo', '-c', 'day='+str(i), input_file, os.path.join(TARGET_DIR, 'readable_sol.lp'), os.path.join(THIS_DIR, 'mashp_daily_scheduler_no_dl.lp')] 
                if settings['sp_obj'] == 'opt':
                    cmd.append(os.path.join(THIS_DIR, 'mashp_daily_scheduler_obj_func.lp'))   
                elif settings['sp_obj'] == 'sat':
                    cmd.append(os.path.join(THIS_DIR, 'mashp_daily_scheduler_sat_constr.lp'))   
                if settings['nogood'] == 'greedy': #solo nel caso greedy, non puo' rifiutare cose che ho assegnato all'iterazione percedente
                    cmd.append(os.path.join(TARGET_DIR, 'nogood.lp'))
                if settings['split_patients'] == 'yes':
                    cmd.append(split_pat_file_fix_sol)
                process = subprocess.Popen(cmd, stdout=output_file, stderr=output_file)
                p_list.append(process)
            for process in p_list:
                process.wait()
            for output_file in output_file_l:
                output_file.close()

            #%prendo il tempo di terminazione di tutti i SP
            nowS_stop = datetime.now()
            #%current_time = nowS_stop.strftime("%H:%M:%S")
            #%print("Stop Time S{}  =".format(iter_counter), current_time)
            
            #%################################################################################################
            #%QUESTA VA TOLTA MI RACCOMANDO, e' SOLO PER PROVARE
            #%if iter_counter==2:
            #%    with open(os.path.join(TARGET_DIR, 'daily_agenda2.lp'), 'w') as cambio:
            #%        cambio.write('UNSATISFIABLE')
            #%################################################################################################

            #%a questo punto devo raccogliere le info degli SP per generare i cut da aggiungere al MP
            cut_d = collect_info()
            #%print('NUOVO TAGLIO:\n'+str(cut_d)+'\n')
            
            #%Devo terminare quando non ho scartati e la soluzione MP e' confermata dai SP
            if settings['nogood']=='greedy' and \
                all(sd[1]['unsat'] == []                           for sd in cut_d.items()) and \
                all(all(el in greedy_fixed for el in sd[1]['sat']) for sd in cut_d.items()):
                print("MASTER PLAN fully confirmed.\n")
                cut_d = {}

            #%dopo ogni iterazione inserisco i tempi salvati nel dizionario apposito
            timestamp_dict[iter_counter]={'M_tot'      :    (nowM_start, nowM_stop), 
                                      'M_grounding'    :    (nowM_start, nowM_gr_stop),
                                      'M_solving'      :    (nowM_gr_stop, nowM_stop),
                                      'S_tot'          :    (nowS_start, nowS_stop)
                                      }

            #%salvo le info dei risultati, ad ogni iterazione per multishot (append!)        
            search_file = glob.glob(os.path.join(TARGET_DIR, 'daily_agenda*.lp'))
            search_file = [f for f in search_file if not re.search('_p.\.lp', f)]
            #%salvo la sol del master
            info_dict={'mp' : get_result_values(os.path.join(TARGET_DIR, 'sol.lp'))}
            #%salvo le sol dei SP
            for fsp in search_file:
                info_dict['sp{}'.format(fsp.split('daily_agenda')[-1].split('.lp')[0])] = get_result_values(fsp)
            info_iter_sol_dict[iter_counter]=info_dict
            with open(os.path.join(TARGET_DIR, 'sol_info.json'), 'w') as sol_info_file: #lo faccio ad ogni iteraz. cosi' si puo' monitorare, ma posso farlo al termine
                json.dump(info_iter_sol_dict, fp=sol_info_file, indent=4)

        #%printo la durata di ciascuna iterazione e salvo il file dei tempi di grounding e solving
        #%for i in range(1,iter_counter+1):
        #%    print("Durata {} = ".format(i)+str(timestamp_dict[i]['S_tot'][1] - timestamp_dict[i]['M_tot'][0]))
        with open(os.path.join(PARENT_DIR, 'target', 'time_info.json'), 'w') as tinfo_file:
            json.dump(str_format_times_dict(timestamp_dict), tinfo_file, indent=4)
#%END IF multishot
#% IF NO_MULTISHOT
    if settings['model'] == 'no_multishot':
        complete_timestamp_list=[]   #una lista perche' non sa a che iterazione ci troviamo col no_multishot, lo sa solo just_mashp.py
        if os.path.isfile(os.path.join(PARENT_DIR, 'target', 'time_info.json')): 
            with open(os.path.join(PARENT_DIR, 'target', 'time_info.json'), 'r') as tinfo_file:
                complete_timestamp_list = json.load(tinfo_file)
        complete_timestamp_list.append(str_format_times_dict(timestamp_dict)[1])
        with open(os.path.join(PARENT_DIR, 'target', 'time_info.json'), 'w') as tinfo_file:
            json.dump(complete_timestamp_list, tinfo_file, indent=4)
#END IF NO_MULTISHOT

def main(prg):
    #%leggo i settings dal file json
    settings={}
    with open(os.path.join(THIS_DIR, 'settings.json')) as settings_file:
        settings=json.load(settings_file)
#%## IF multishot OR no_multishot
    if settings['model'] in ['multishot', 'no_multishot']:
        main_iterativo(prg, settings)
#%## ELSE monolitico...
    elif settings['model'] == 'monolithic':
    	main_monolitico(prg)
    
#end.
