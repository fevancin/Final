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
