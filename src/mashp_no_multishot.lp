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

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% SUSSUNZIONE SEMPLICE %%%%%%%%%%%%%%%%%%%%%%%%
%subsumes(DN, DM) :-
%    horizon(DN), horizon(DM),
%    day_worker_subsumed(DN,OP_ID,StartDM,StopDM):operator_shift(DM, OP_ID, StartDM, StopDM).

day_resource_subsumes(D, D, CU) :- horizon(D), resource(CU).
day_resource_subsumes(DN,DM,CU) :- horizon(DN), horizon(DM), resource(CU),
                                    day_worker_subsumed(DN,(CU,ID),StartDM,StopDM):operator_shift(DM, (CU,ID), StartDM, StopDM).

                                    

%sussunzione singolo operatore se uno è incluso temporalmente nell'altro
day_worker_subsumed(DN,(CU,ID2),StartDM,StopDM):-
    operator_shift(DM,(CU,ID1),StartDM,StopDM),
    operator_shift(DN,(CU,ID2),StartDN,StopDN),
    StartDN<=StartDM, StopDN>=StopDM.

%DEF
resource(CU):-capacity(_,CU,_,_,_).
operator_shift(DN,(CU,ID),StartDN,StartDN+Dur) :- capacity(DN,CU,ID,StartDN,Dur).
giorno(D):-capacity(D,_,_,_,_).
operatore(D,(CU,ID)):-operator_shift(D,(CU,ID),_,_).

#program sussunzione_matching.
%%%  SUSSUNZIONE GIORNATE  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%Dico che un giorno sussume un altro se lo sussume per tutte le risorse
%subsumes(DN, DM) :-
%    giorno(DN), giorno(DM),
%    day_resource_subsumes(DN,DM,CU):capacity(DM, CU, _, _, _).

%sussunzione singolo operatore se uno è incluso temporalmente nell'altro
day_worker_subsumed(DN,(CU,ID2),DM,(CU,ID1)):-
    operator_shift(DM,(CU,ID1),StartDM,StopDM),
    operator_shift(DN,(CU,ID2),StartDN,StopDN),
    StartDN<=StartDM, StopDN>=StopDM.

%SUSSUNZIONE RISORSE COME MATCHING
%gli archi sono rappresentati dalle sussunzioni tra operatori di due giorni diversi
arc(DN,DM,(DN,CU,IDN),(DM,CU,IDM)) :- day_worker_subsumed(DN,(CU,IDN),DM,(CU,IDM)), DM!=DN.
%simmetria sul grafo, notare che DN,DM e DM,DN rappresentano 2 grafi distinti, ciascuno per chi sussume chi
arc(DN,DM,VE,VS) :- arc(DN,DM,VS,VE), DM!=DN.

%devo selezionare degli archi come Match
{match(DN,DM,VS,VE)}1 :- DN!=DM, arc(DN,DM,VS,VE).
match(DN,DM,VE,VS) :- match(DN,DM,VS,VE).

% un match ha cardinalità <=1 dei nodi
:- match(DN,DM,VS,VE1), match(DN,DM,VS,VE2), VE1!=VE2.

%OTTIMALITA': assenza di cammino alternante aumentante --> MAX MATCH
%Base: alternato se c'é un arco vuoto
alternating_path(DN,DM,VS,VE):-
    arc(DN,DM,VS,VE),
    not match(DN,DM,VS,VE).

%ricorsione: alternato se alternato + arco in M + arco vuoto concatenato
alternating_path(DN,DM,VS,VE):-
    alternating_path(DN,DM,VS,VX),
    match(DN,DM,VX,VY),
    arc(DN,DM,VY,VE),
    not match(DN,DM,VY,VE).

%Vieto la presenza di cammino alternante aumentante i.e. che parte e termina in nodi liberi
:- alternating_path(DN,DM,VS,VE),
    not match(DN,DM,VS,VX):arc(DN,DM,VS,VX);
    not match(DN,DM,VY,VE):arc(DN,DM,VY,VE).

%Sussunzione risorse se la cardinalità del match è massima, ovvero pari alla cardinalità dei sussunti (DM)
day_resource_subsumes(D, D, CU) :- giorno(D), resource(CU).
day_resource_subsumes(DN,DM,CU) :- giorno(DN), giorno(DM), resource(CU),
                                    Card_match = #count{IDM : match(DN,DM,(DN,CU,_),(DM,CU,IDM))},
                                    DM_op=#count{ID:capacity(DM,CU,ID,_,_)},
                                    Card_match=DM_op.

%DEF
resource(CU):-capacity(_,CU,_,_,_).
operator_shift(DN,(CU,ID),StartDN,StartDN+Dur) :- capacity(DN,CU,ID,StartDN,Dur).
giorno(D):-capacity(D,_,_,_,_).
operatore(D,(CU,ID)):-operator_shift(D,(CU,ID),_,_).

%#show subsumes/2.
%#show day_resource_subsumes/3.
%#show day_worker_subsumed/4.
%#show match/4.
%#show alternating_path/4.
#program base.

%%% NOGOOD NAIVE %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
grp(Day,Grp):-nogood(_, _, Day, Grp).
:- schedule(Pat, Pkt, Day) : nogood(Pat, Pkt, Day, Grp); 
    grp(Day, Grp),
    naive.

%%% NOGOOD UNSAT CORE BASIC %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
grp(Day,Iid,Gid):-nogood_cut(_, _, Day, Iid, Gid).
:- schedule(Pat, (Pkt_ID, _), Day) : nogood_cut(Pat, Pkt_ID, Day, Iid, Gid);
    grp(Day, Iid, Gid),
    basic.
    
%%% NOGOOD UNSAT CORE REDUCTED WITH NAMES --> MEMORY ERROR with all combinations %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
grp(Day,Iid,Gid):-nogood_cut(_, _, Day, Iid, Gid).
:- schedule_srv(Day, Pat, Srv) : multipacket_nogood_with_names(Pat, Srv, Day, Iid, Gid); 
    grp(Day,Iid,Gid),
    named_mpk.


%%% NOGOOD UNSAT CORE REDUCTED (with propagation) %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

multipacket_nogood(Multi, MID, Srv, SubDay, IID, GID) :- multipacket_nogood(Multi, MID, Srv, Day, IID, GID), horizon(SubDay),
                                                        day_resource_subsumes(Day, SubDay, Res):multipacket(Multi,SrvX), service(SrvX, Res, _, _).

mpkt_nogood(Multi, MID, Day, IID, GID) :- multipacket_nogood(Multi, MID, Srv, Day, IID, GID).
multipacket(Multi, Srv)                :- multipacket_nogood(Multi, MID, Srv, Day, IID, GID).
multipacket(S,S):-service(S,_,_,_).

%DEF
basic_nogood_bunch_id((D,IID,GID)) :- mpkt_nogood(_,_,D,IID,GID).

nogood_srv_link(ID, (Multi,MID), Pat, Srv) :- pat_nogood(ID, (Multi,MID), Pat),
                                              multipacket(Multi, Srv).

%DEVO TAGLIARE SOLUZIONI CHE NON RISPETTANO I NOGOOD
%creo i link possibili
%schedule_multipacket((D,IID,GID), (Multi,MID), Pat):-
%    mpkt_nogood(Multi,MID, D,IID,GID), patient(Pat), horizon(D),
%    schedule_srv(D,Pat,Srv) : multipacket(Multi,Srv).   


%DEF: schedula una prestazione che richiede stessa risorsa ma in quantità maggiore
schedule_GE_srv(D,Pat,Srv_GE,Srv_LE) :- schedule_srv(D,Pat,Srv_GE),
                                        service(Srv_GE, Res, Dur_GE, _), 
                                        service(Srv_LE, Res, Dur_LE, _),
                                        Dur_GE>=Dur_LE.

%qui potrei dire che hanno stessa risorsa e durata > : service(Srv, Res)
%Quindi: esiste un possibile collegamento tra un multipacket nogood (di un certo gruppo)
% e un paziente se questo schedula nel giorno di validità del nogood tutti servizi di durata
% maggiore o uguale a ciascuno di quelli del multipacket nogood, a parità di risorsa richiesta
schedule_multipacket((D,IID,GID), (Multi,MID), Pat):-
    mpkt_nogood(Multi,MID, D,IID,GID), patient(Pat), horizon(D),
    schedule_GE_srv(D,Pat,Srv_GE, Srv_LE) : multipacket(Multi,Srv_LE).



%generate selezione archi
{pat_nogood((D,IID,GID), (Multi,MID), Pat):schedule_multipacket((D,IID,GID), (Multi,MID), Pat)}1 :- mpkt_nogood(Multi,MID, D,It,GID).

% Pat non associato a nogood che condividono pacchetti 
:-  pat_nogood(ID, (Multi1,MID1), Pat), 
    pat_nogood(ID, (Multi2,MID2), Pat),
    Multi1!=Multi2,
    share_packet(Multi1,Multi2).

%AUX DEF
linked_nogood(ID, NG) :- pat_nogood(ID, NG, Pat). 
linked_pat(ID, Pat)   :- pat_nogood(ID, NG, Pat).
linked_pat_srv(ID, Pat,Srv) :- pat_nogood(ID, (Multi,MID), Pat), multipacket(Multi, Srv).

%Non posso avere un nogood non collegato, se c'é un paziente che ha i servizi del nogood non associati a nessuno
:- mpkt_nogood(Multi, MID, D,It,GID),
    not linked_nogood((D,It,GID), (Multi,MID)),
    schedule_multipacket((D,It,GID), (Multi,MID), Pat),
    not linked_pat_srv((D,It,GID), Pat, Srv) : multipacket(Multi, Srv).

%Non ammetto soluzioni che associano tutti i nogood
:- linked_nogood((D,It,GID), (Multi,MID)):mpkt_nogood(Multi,MID, D,It,GID); 
    basic_nogood_bunch_id((D,It,GID)),
    mpk.

%condivide pacchetto se hanno un pacchetto in comune
share_packet(M1, M2) :- multipacket(M1, R), multipacket(M2, R).


%#show pat_nogood/3.
%#show schedule_multipacket/3.
%#show mpkt_nogood/5.
%#show multipacket/2.
%#show multipacket_nogood/6.
%#show schedule_srv/3.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% #script (python)

% import glob
% from clingo import Number, String, Function, parse_term
% import subprocess
% import os
% import sys
% import re
% import json
% from datetime import datetime

% THIS_DIR_tmp  =   '/home/marco/Universita/Dottorato/Studi/Progetto NCDs Agenda/Tesi Vancini/Final'
% THIS_DIR_name =   'src'#THIS_DIR_tmp.split('<')[1]
% THIS_DIR      =   os.path.join(THIS_DIR_tmp.split('<')[0], THIS_DIR_name)
% PARENT_DIR    =   os.path.abspath(os.path.join(THIS_DIR, '..'))
% TARGET_DIR    =   os.path.join(PARENT_DIR, 'target')
% #print(os.path.dirname(os.path.realpath(sys.argv[0])))  #subprocess con pipe per ritornare lettura

% sys.path.append(THIS_DIR)

% split_pat_file_fix_sol = os.path.join(TARGET_DIR, 'fixed_sol.lp')

% from mashp_tools import read_ASP, get_cur_dir, str_format_times_dict, get_result_values
% from collect4cut import collect_info


% def breakpoint():
%     go=False
%     while not go or go=='':
%         with open("pass.txt") as p:
%             go=p.read()
%     with open("pass.txt", 'w') as p:
%         p.write('')


% def main_monolitico(prg):

%     #%###################################################
%     #%                 Master Problem                   #
%     #%###################################################

%     #%prendo il tempo di start della prima iterazione MP  
%     nowM_start = datetime.now()
%     #%current_time = nowM_start.strftime("%H:%M:%S")
%     #%print("\n\nStart Time M1 =", current_time)

%     #%avvio grounding e solving del problema com'e' in origine
%     prg.ground([("base", [])])
    
%     nowM_gr_stop = datetime.now()
    
%     prg.solve()

%     nowM_stop = datetime.now()
%     #%current_time = nowM_stop.strftime("%H:%M:%S")
%     #%print("Stop Time M1  =", current_time)

%     #%al termine devo scrivere la soluzione nel file 'readable_sol.lp'
%     #%e lo faccio con l'apposito script 
%     cmd=['python', os.path.join(PARENT_DIR, 'format_master_plan.py')]
%     process = subprocess.Popen(cmd)
%     process.wait()

%     with open(os.path.join(TARGET_DIR, 'time_info.json'), 'w') as time_info_file:
%         json.dump({"Grounding Time" : str(nowM_gr_stop - nowM_start),
%                    "Solving Time"   : str(nowM_stop    - nowM_gr_stop)}, time_info_file, indent=4)

%     print("Durata = "+str(nowM_stop - nowM_start))


% def main_iterativo(prg, settings):
%     #%Getting horizon dimension from input file
%     input_file=os.path.join(PARENT_DIR, "input", "mashp_input.lp")
%     l_input = read_ASP(input_file)
%     nh = None
%     for f in l_input:
%         #%find the horizon constant
%         if 'nh=' in f:
%             horizon_l=re.split('\=|\.', f)
%             nh=int(horizon_l[-2])
%             break

%     #%print('\n*** nh = '+str(nh)+' ***\n')

%     #%###################################################
%     #%                 Master Problem                   #
%     #%###################################################
    
%     #%dizionari dei timestamp e dei risultati per controllare i tempi di solving
%     timestamp_dict={}
%     info_iter_sol_dict={}
%     #%prendo il tempo di start della prima iterazione MP  
%     nowM_start = datetime.now()
%     #current_time = nowM_start.strftime("%H:%M:%S")
%     #print("\n\nStart Time M1 =", current_time)

%     solve_result=None
% #IF multishot...
%     if settings['model']=='multishot':

%         tl_init=settings["first_iter_tl"]
%         tl_incr=settings["iter_tl_incr"]

%         #%avvio grounding e solving del problema com'e' in origine
%         prg.ground([("base", [])])
%         nowM_gr_stop = datetime.now()
%         #prg.solve()
%         with prg.solve(async_ = True, yield_ = False) as handle:
%             optim = handle.wait(tl_init)
%             #print(optim)
%             if optim:
%                 print("OPTIMUM REACHED")
%             else:
%                 print("NOT PROVEN OPTIMALITY")
%     ##    solve_result=handle.get()
%         nowM_stop = datetime.now()
%         #current_time = nowM_stop.strftime("%H:%M:%S")
%         #print("Stop Time M1  =", current_time)

% #ELSE IF no_multishot...
%     elif settings['model']=='no_multishot':
%         #%avvio grounding e solving del problema com'e' in origine
%         prg.ground([("base", [])])
%         nowM_gr_stop = datetime.now()
%         #%prg.solve()
%         time_limit=0
%         with open(os.path.join(THIS_DIR, "time_limit.json")) as tl_file:
%             tl_d=json.load(tl_file)
%             tl=int(tl_d["tl"])
%         with prg.solve(async_ = True, yield_ = False) as handle:        
%             optim = handle.wait(tl)
%             if optim:
%                 print("OPTIMUM REACHED")
%             else:
%                 print("NOT PROVEN OPTIMALITY")
%     ###        solve_result=handle.get()
%         nowM_stop = datetime.now()
%         #current_time = nowM_stop.strftime("%H:%M:%S")
%         #print("Stop Time M1  =", current_time)
	    
% #END IF ELSE
	    
%     #%al termine devo scrivere la soluzione nel file 'readable_sol.lp'
%     #%e lo faccio con l'apposito script 
%     cmd=['python', os.path.join(PARENT_DIR, 'format_master_plan.py')]
%     process = subprocess.Popen(cmd)
%     process.wait()


%     #%###################################################
%     #%                   Sub Problem                    #
%     #%###################################################
%     #%Nota che agisce anche se il Master e' diventato UNSAT.
%     #%In questo modo aggiorno tutte le soluzioni giornaliere (che fa terminare il loop)
%     #%MA potrebbe essere rimosso e fatto agire solo per sol. SAT.

% #%IF multishot...
%     #if settings['model']=='multishot':
%         #%prendo il tempo di inizio di tutti i SP
%     nowS_start = datetime.now()
%         #current_time = nowS_start.strftime("%H:%M:%S")
%         #print("Start Time S1 =", current_time)
% #%END IF multishot

%     #%terminato il solving devo avviare tutti i SP per ciascun giorno (nh)
%     p_list=[]
%     output_file_l=[]
%     for i in range(1, nh+1):
%         output_file=open(os.path.join(TARGET_DIR, 'daily_agenda{}.lp'.format(i)), 'w')
%         output_file_l.append(output_file)
%         if settings['sp_dl'] == 'yes':
%             cmd = ['clingo-dl', '-c', 'day='+str(i), input_file, os.path.join(TARGET_DIR, 'readable_sol.lp'), os.path.join(THIS_DIR, 'mashp_daily_scheduler.lp')]
%         else:
%             cmd = ['clingo', '-c', 'day='+str(i), input_file, os.path.join(TARGET_DIR, 'readable_sol.lp'), os.path.join(THIS_DIR, 'mashp_daily_scheduler_no_dl.lp')]
%         if settings['sp_obj'] == 'opt':
%             cmd.append(os.path.join(THIS_DIR, 'mashp_daily_scheduler_obj_func.lp'))
%         elif settings['sp_obj'] == 'sat':
%             cmd.append(os.path.join(THIS_DIR, 'mashp_daily_scheduler_sat_constr.lp'))
%         if settings['nogood'] == 'greedy': #solo nel caso greedy, non puo' rifiutare cose che ho assegnato all'iterazione percedente
%             cmd.append(os.path.join(TARGET_DIR, 'nogood.lp'))
%         if settings['split_patients'] == 'yes':
%             if os.path.isfile(split_pat_file_fix_sol):
%                 cmd.append(split_pat_file_fix_sol)
%         process = subprocess.Popen(cmd, stdout=output_file, stderr=output_file)
%         if settings['parallelize_sp'] == 'no':
%             process.wait()
%         else:
%             p_list.append(process)
%     for process in p_list:
%         process.wait()
%     for output_file in output_file_l:
%         output_file.close()

%     #%prendo il tempo di terminazione di tutti i SP
%     nowS_stop = datetime.now()
%     #current_time = nowS_stop.strftime("%H:%M:%S")
%     #print("Stop Time S1  =", current_time)

%     iter_counter=1
%     #%dopo la prima iterazione inserisco i tempi salvati nel dizionario apposito
%     timestamp_dict[iter_counter]={'M_tot'      :    (nowM_start, nowM_stop), 
%                                   'M_grounding':    (nowM_start, nowM_gr_stop),
%                                   'M_solving'  :    (nowM_gr_stop, nowM_stop),
%                                   'S_tot'      :    (nowS_start, nowS_stop)
%                                   }

% #%IF multishot...
%     if settings['model']=='multishot':

%         #salvo le info dei risultati della prima iterazione      
%         search_file = glob.glob(os.path.join(TARGET_DIR, 'daily_agenda*.lp'))
%         search_file = [f for f in search_file if not re.search('_p.\.lp', f)]
%         #salvo la sol del master
%         info_dict={'mp' : get_result_values(os.path.join(TARGET_DIR, 'sol.lp'))}
%         #salvo le sol dei SP
%         for fsp in search_file:
%             info_dict['sp{}'.format(fsp.split('daily_agenda')[-1].split('.lp')[0])] = get_result_values(fsp)
%         info_iter_sol_dict[iter_counter]=info_dict
%         with open(os.path.join(TARGET_DIR, 'sol_info.json'), 'w') as sol_info_file: #lo faccio ad ogni iteraz. cosi' si puo' monitorare, ma posso farlo al termine
%             json.dump(info_iter_sol_dict, sol_info_file, indent=4)

%         #%########################################################################
%         #%QUESTA VA TOLTA MI RACCOMANDO, e' SOLO PER PROVARE
%         #%with open(os.path.join(TARGET_DIR, 'daily_agenda1.lp'), 'w') as cambio:
%         #%    cambio.write('UNSATISFIABLE')
%         #%#########################################################################

%         #%Flag per evitare loop in caso sia insoddisfacibile già il MP all'inizio
%         #%UNSAT=False
%         #%with open(os.path.join(TARGET_DIR, 'readable_sol.lp'), 'r') as s_file:
%         #%    line=s_file.readline()
%         #%    while(line):
%         #%        if 'UNSATISFIABLE' in line:
%         #%            UNSAT=True
%         #%            break
%         #%        line=s_file.readline()    

%         #%a questo punto devo raccogliere le info degli SP per generare i cut da aggiungere al MP
%         cut_d = collect_info()
%         #print('\n'+str(cut_d)+'\n')

%         greedy_fixed=[] #per evitare di ripetere valori fissati gia' in precedenza
%         #%finche' esistono agende giornaliere non ammissibili, itero aggiungendo clausole di no-good
%         while cut_d: #% and not UNSAT:

%             #%%%%%%%%%%%%
%             #breakpoint() #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%             #%%%%%%%%%%%%

%             #%###################################################
%             #%                 Master Problem                   #
%             #%###################################################

%             #%catturo il timestamp dell'inizio della seconda iterazione
%             nowM_start = datetime.now()
%             #current_time = nowM_start.strftime("%H:%M:%S")
%             #print("Start Time M{} =".format(str(iter_counter)), current_time)

%             #%check if timeout is reached
%             if os.path.exists(os.path.join(PARENT_DIR, 'test', 'tmp_time_limit.json')):
%                 with open(os.path.join(PARENT_DIR, 'test', 'tmp_time_limit.json'), 'r') as tmp_tl_file:
%                     tmp_tl_d=json.load(tmp_tl_file)

%     # DEBUG #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%            
%     #            with open(os.path.join(PARENT_DIR, 'debug.txt'), 'a+') as dbg:
%     #                dbg.write(datetime.strftime(datetime.strptime(tmp_tl_d['end'], '%y-%m-%d %H:%M:%S'), '%y-%m-%d %H:%M:%S'))
%     #                dbg.write('\t')
%     #                dbg.write(datetime.strftime(nowM_start, '%y-%m-%d %H:%M:%S'))
%     #                dbg.write('\n')
%     #%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
                
%                 if datetime.strptime(tmp_tl_d['end'], '%y-%m-%d %H:%M:%S')<=nowM_start:
%                     break

%             #%devo creare una lista di elementi da rendere ground all'interno del programma nogood
%             #%che contiene le informazioni raccolte sul nogood da inserire, i.e. ogni termine della
%             #%nuova clausola 
%             add_ground=[]

%             #MODELLO GREEDY
%             if settings['nogood'] == 'greedy':
%                 with open(os.path.join(TARGET_DIR, 'nogood.lp'), 'a') as ng:
%                     if iter_counter == 1: ng.write('greedy.\n')
%                     index_printed=False
%                     for day,l in cut_d.items():
%                         #print("fisso soluzioni della data"+' '+str(day)+' '+str(l))
%                         for t in l['sat']:
%                             if not t in greedy_fixed:
%                                 add_ground.append(("greedy", [parse_term('sat'),parse_term(t[0]), parse_term(t[1]), Number(int(t[2])), Number(int(t[3])), Number(int(t[4])), Number(int(t[5]))]))
%                                 greedy_fixed.append(t)
%                                 if not index_printed:
%                                     ng.write(f"%Iter: {iter_counter}\n")
%                                     index_printed=True
%                                 ng.write("fix_schedule({},{},{},{},{},{}).\n".format(t[0], t[1], t[2], t[3], t[4], t[5]))
%                         for t in l['unsat']:
%                             add_ground.append(("greedy", [parse_term('unsat'),parse_term(t[0]), parse_term(t[1]), Number(int(t[2])), Number(int(t[3])), Number(int(t[4])), Number(int(t[5]))]))
%                             if not index_printed:
%                                 ng.write(f"%Iter: {iter_counter}\n")
%                                 index_printed=True
%                             ng.write("not_schedulable({},(({},{},{}),{}),{}).\n".format(t[0], t[1], t[2], t[3], t[4], t[5]))


%             #%VERSIONE NAIVE
%             if settings['nogood'] == 'naive':
%                 for day,l in cut_d.items():
%                     print("aggiungo vincolo della data"+' '+str(day))#%+' '+str(l))
%                     for t in l:
%                         add_ground.append(("nogood", [parse_term(t[0]), parse_term(t[1]), Number(int(t[2])), Number(int(t[3])), Number(int(t[4])), Number(int(t[5])), Number(iter_counter)]))
%                         #%qui sto usando iter_counter come ID del gruppo di pazienti, potrebbe essere necessario diverso
%                         #%qualora si trovassero piu' gruppi alla stessa iterazione


%             #%VERSIONE UNSAT CORES singolo giorno (BASIC)
%             elif settings['nogood'] == 'basic_unsat_core':
%                 gid=0
%                 for day,l in cut_d.items():
%                     for grp in l:
%                         print("aggiungo vincolo della data"+' '+str(day))#%+' '+str(grp))
%                         for t in grp:
%                             add_ground.append(("nogood_cut", [parse_term(t[0]), parse_term(t[1]), Number(int(t[2])), Number(int(t[3])), Number(int(day)), Number(iter_counter), Number(gid)]))
%                         gid+=1
            

%             #%VERSIONE UNSAT CORES RIDOTTI singolo giorno [multipacchetti con nome] (NAIVE)   -- usa cut_d dei multipacket
%             elif settings['nogood'] == 'multipacket_with_names1':
%                 for day,gd in cut_d.items():
%                     for gid, mpkt_d in gd.items():
%                         print("aggiungo vincolo della data"+' '+str(day))#%+' '+str(gid))
%                         for mpkt_id,pat_name in enumerate(mpkt_d):
%                             mpkt_label = '_'.join(sorted(mpkt_d[pat_name]))
%                             for srv in mpkt_d[pat_name]:
%                                 #print([pat_name, mpkt_label, srv, int(day), iter_counter, gid])
%                                 add_ground.append(("multipacket_nogood_with_names", [parse_term(pat_name), parse_term(mpkt_label), parse_term(srv), Number(int(day)), Number(int(iter_counter)), Number(int(gid))]))        


%             #%VERSIONE UNSAT CORES COMBINAZIONE TUTTI I NOMI
%             elif settings['nogood'] == 'multipacket_with_names2':
%                 for day,group_d in cut_d.items():
%                     for gid, group_l in group_d.items():
%                         for mpkt_id,mpkt in enumerate(group_l):
%                             mpkt_label='_'.join(sorted(mpkt[1]))
%                             for srv in mpkt[1]:
%                                 add_ground.append(("multipacket_nogood_with_names", [parse_term(mpkt[0]), 
%                                                                                     parse_term(mpkt_label), 
%                                                                                     #%int(mpkt_id), 
%                                                                                     parse_term(srv), 
%                                                                                     Number(int(day)), 
%                                                                                     iter_counter, gid]))

%             #%VERSIONE UNSAT CORES MULTIPACKETS : INSERIMENTO CORRETTO MA NON FUNZIONA ASP
%             elif settings['nogood'] == 'multipacket_unsat_core':
%                 for day,gd in cut_d.items():
%                     for gid, mpkt_d in gd.items():
%                         print("aggiungo vincolo della data"+' '+str(day))#%+' '+str(gid))
%                         for mpkt_id,pat_name in enumerate(mpkt_d):
%                             mpkt_label = '_'.join(sorted(mpkt_d[pat_name]))
%                             for srv in mpkt_d[pat_name]:
%                                 #print([pat_name, mpkt_label, mpkt_id, srv, int(day), iter_counter, gid])
%                                 add_ground.append(("multipacket_nogood", [parse_term(mpkt_label), Number(int(mpkt_id)), parse_term(srv), Number(int(day)), Number(iter_counter), Number(gid)]))        
            
%             print("ITER COUNTER = ",iter_counter)
%             #%aggiungo gli elementi al programma
%             #%e.g.
%             #%prg.ground([("nogood", [parse_term("joeanthony"),parse_term("pi74"),3,1,3,132,4]),  %[paz, prot, iter, pacc, occ, giorno, gid]
%             #%           ("nogood", [parse_term("gaelan"),parse_term("pi529"), 2,1,1,132,3])])
            
%             #%if iter_counter>1:
%             #%    prg.release_external(Function("q", [iter_counter-1]))
%             #%prg.cleanup()
%             nowM_gr_start = datetime.now()
%             nowM_gr_stop = nowM_gr_start
%             if add_ground:
%             #%    prg.assign_external(Function("q", [iter_counter]), True)
%                 prg.ground(add_ground)
%                 #prg.ground([("base",[])])
%                 nowM_gr_stop = datetime.now()
%             # prg.solve() #%no timeout
%                 try:
%                     with prg.solve(async_ = True, yield_ = False) as handle:
%                         optim = handle.wait(tl_init + tl_incr*iter_counter)
%                         #print(optim)
%                         if optim:
%                             print("OPTIMUM REACHED")
%                         else:
%                             print("NOT PROVEN OPTIMALITY")
%             ##            solve_result=handle.get()
%                 except:
%                     print("terminazione")
%             iter_counter+=1

%             #%catturo il tempo di termine della seconda iterazione
%             nowM_stop = datetime.now()
%             #current_time = nowM_stop.strftime("%H:%M:%S")
%             #print("Stop Time M{}  =".format(iter_counter), current_time)

%             #%creo il file readable_sol.lp
%             cmd=['python', os.path.join(PARENT_DIR, 'format_master_plan.py')]
%             process = subprocess.Popen(cmd)
%             process.wait()


%             #%###################################################
%             #%                    Sub Problem                   #
%             #%###################################################
%             #%Nota che agisce anche se il Master e' diventato UNSAT.
%             #%In questo modo aggiorno tutte le soluzioni giornaliere (che fa terminare il loop)
%             #%MA potrebbe essere rimosso e fatto agire solo per sol. SAT.

%             #%catturo il timestamp dell'inizio della seconda iterazione
%             nowS_start = datetime.now()
%             #%current_time = nowS_start.strftime("%H:%M:%S")
%             #%print("Start Time S{} =".format(iter_counter), current_time)

%             #%terminato il solving devo avviare tutti i SP per ciascun giorno (nh)
%             p_list=[]
%             output_file_l=[]
%             for i in range(1, nh+1):
%                 output_file=open(os.path.join(TARGET_DIR, 'daily_agenda{}.lp'.format(i)), 'w')
%                 output_file_l.append(output_file)
%                 if settings['sp_dl'] == 'yes':
%                     cmd = ['clingo-dl', '-c', 'day='+str(i), input_file, os.path.join(TARGET_DIR, 'readable_sol.lp'), os.path.join(THIS_DIR, 'mashp_daily_scheduler.lp')]
%                 else:
%                     cmd = ['clingo', '-c', 'day='+str(i), input_file, os.path.join(TARGET_DIR, 'readable_sol.lp'), os.path.join(THIS_DIR, 'mashp_daily_scheduler_no_dl.lp')] 
%                 if settings['sp_obj'] == 'opt':
%                     cmd.append(os.path.join(THIS_DIR, 'mashp_daily_scheduler_obj_func.lp'))   
%                 elif settings['sp_obj'] == 'sat':
%                     cmd.append(os.path.join(THIS_DIR, 'mashp_daily_scheduler_sat_constr.lp'))   
%                 if settings['nogood'] == 'greedy': #solo nel caso greedy, non puo' rifiutare cose che ho assegnato all'iterazione percedente
%                     cmd.append(os.path.join(TARGET_DIR, 'nogood.lp'))
%                 if settings['split_patients'] == 'yes':
%                     cmd.append(split_pat_file_fix_sol)
%                 process = subprocess.Popen(cmd, stdout=output_file, stderr=output_file)
%                 p_list.append(process)
%             for process in p_list:
%                 process.wait()
%             for output_file in output_file_l:
%                 output_file.close()

%             #%prendo il tempo di terminazione di tutti i SP
%             nowS_stop = datetime.now()
%             #%current_time = nowS_stop.strftime("%H:%M:%S")
%             #%print("Stop Time S{}  =".format(iter_counter), current_time)
            
%             #%################################################################################################
%             #%QUESTA VA TOLTA MI RACCOMANDO, e' SOLO PER PROVARE
%             #%if iter_counter==2:
%             #%    with open(os.path.join(TARGET_DIR, 'daily_agenda2.lp'), 'w') as cambio:
%             #%        cambio.write('UNSATISFIABLE')
%             #%################################################################################################

%             #%a questo punto devo raccogliere le info degli SP per generare i cut da aggiungere al MP
%             cut_d = collect_info()
%             #%print('NUOVO TAGLIO:\n'+str(cut_d)+'\n')
            
%             #%Devo terminare quando non ho scartati e la soluzione MP e' confermata dai SP
%             if settings['nogood']=='greedy' and \
%                 all(sd[1]['unsat'] == []                           for sd in cut_d.items()) and \
%                 all(all(el in greedy_fixed for el in sd[1]['sat']) for sd in cut_d.items()):
%                 print("MASTER PLAN fully confirmed.\n")
%                 cut_d = {}

%             #%dopo ogni iterazione inserisco i tempi salvati nel dizionario apposito
%             timestamp_dict[iter_counter]={'M_tot'      :    (nowM_start, nowM_stop), 
%                                       'M_grounding'    :    (nowM_start, nowM_gr_stop),
%                                       'M_solving'      :    (nowM_gr_stop, nowM_stop),
%                                       'S_tot'          :    (nowS_start, nowS_stop)
%                                       }

%             #%salvo le info dei risultati, ad ogni iterazione per multishot (append!)        
%             search_file = glob.glob(os.path.join(TARGET_DIR, 'daily_agenda*.lp'))
%             search_file = [f for f in search_file if not re.search('_p.\.lp', f)]
%             #%salvo la sol del master
%             info_dict={'mp' : get_result_values(os.path.join(TARGET_DIR, 'sol.lp'))}
%             #%salvo le sol dei SP
%             for fsp in search_file:
%                 info_dict['sp{}'.format(fsp.split('daily_agenda')[-1].split('.lp')[0])] = get_result_values(fsp)
%             info_iter_sol_dict[iter_counter]=info_dict
%             with open(os.path.join(TARGET_DIR, 'sol_info.json'), 'w') as sol_info_file: #lo faccio ad ogni iteraz. cosi' si puo' monitorare, ma posso farlo al termine
%                 json.dump(info_iter_sol_dict, fp=sol_info_file, indent=4)

%         #%printo la durata di ciascuna iterazione e salvo il file dei tempi di grounding e solving
%         #%for i in range(1,iter_counter+1):
%         #%    print("Durata {} = ".format(i)+str(timestamp_dict[i]['S_tot'][1] - timestamp_dict[i]['M_tot'][0]))
%         with open(os.path.join(PARENT_DIR, 'target', 'time_info.json'), 'w') as tinfo_file:
%             json.dump(str_format_times_dict(timestamp_dict), tinfo_file, indent=4)
% #%END IF multishot
% #% IF NO_MULTISHOT
%     if settings['model'] == 'no_multishot':
%         complete_timestamp_list=[]   #una lista perche' non sa a che iterazione ci troviamo col no_multishot, lo sa solo just_mashp.py
%         if os.path.isfile(os.path.join(PARENT_DIR, 'target', 'time_info.json')): 
%             with open(os.path.join(PARENT_DIR, 'target', 'time_info.json'), 'r') as tinfo_file:
%                 complete_timestamp_list = json.load(tinfo_file)
%         complete_timestamp_list.append(str_format_times_dict(timestamp_dict)[1])
%         with open(os.path.join(PARENT_DIR, 'target', 'time_info.json'), 'w') as tinfo_file:
%             json.dump(complete_timestamp_list, tinfo_file, indent=4)
% #END IF NO_MULTISHOT

% def main(prg):
%     #%leggo i settings dal file json
%     settings={}
%     with open(os.path.join(THIS_DIR, 'settings.json')) as settings_file:
%         settings=json.load(settings_file)
% #%## IF multishot OR no_multishot
%     if settings['model'] in ['multishot', 'no_multishot']:
%         main_iterativo(prg, settings)
% #%## ELSE monolitico...
%     elif settings['model'] == 'monolithic':
%     	main_monolitico(prg)
    
% #end.
