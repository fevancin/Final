#const overlap=20.
#const not_scheduled_w=1.
% DEF
    %%% -- OCCORRENZA PACCHETTO: è l'istnza da schedulare, e il valore di occorrenza serve al calcolo della data ideale
    %                           a partire dallo start prescritto    
occurrence_to_schedule(Pat, ((Prot, Iter, Pkt_in_Prot), Occ)) :- 
    packet_instance(Pat, Prot, Iter, Pkt_in_Prot), n_occurrences(Pat, Prot, Iter, Pkt_in_Prot, N_occ), Occ=1..N_occ.

    %%% -- CONTIENE PRESTAZIONE: predicato utile per alleggerire la notazione, determina se un pacchetto (istanza) 
        %                           contiene una certa prestazione
service_in_packet(Pat, (Prot, Iter, Pkt), Pr) :- packet_type(Pat, Prot, Iter, Pkt, Type), service_in_packet(Type, Pr).

    %%% -- DATA IDEALE:         Si tratta della data ottenuta sommando il valore della packet_frequency ad ogni occorrenza
    %                           a partire dallo start del pacchetto
ideal_date(Pat, ((Prot, Iter, Pkt), Occ), D) :- occurrence_to_schedule(Pat, ((Prot, Iter, Pkt), Occ)), packet_frequency(Pat, Prot, Iter, Pkt, Freq), 
                                                   packet_start(Pat, Prot, Iter, Pkt, S), protocol_iteration_start(Pat, Prot, Iter, Inizio_prot),
                                                   D=Inizio_prot+S-1+Freq*(Occ-1).

    %%% -- ESTREMI TOLLERANZA:  Estremi della packet_tolerance di ciascuna occorrenza
min_max_tolerance(Pat, ((Prot, Iter, Pkt), Occ), Min, Max) :- occurrence_to_schedule(Pat, ((Prot, Iter, Pkt), Occ)), packet_tolerance(Pat, Prot, Iter, Pkt, Tol),
                                                         ideal_date(Pat, ((Prot, Iter, Pkt), Occ), Data_centrale),
                                                         Min=Data_centrale-Tol,
                                                         Max=Data_centrale+Tol.

    %%% -- GIORNI DI TOLL.:     Raccolgo dai precedenti i singoli giorni candidati allo scheduling dell'occorrenza
within_tolerance(Pat, ((Prot, Iter, Pkt), Occ), (Min..Max)) :- min_max_tolerance(Pat, ((Prot, Iter, Pkt), Occ), Min, Max).

    %%% -- COLLASSAMENTI:       Quando 2 o più prestazioni identiche dello stesso paziente sono allineate lo stesso giorno
    %                           tutte queste valgono come 1 (non ha senso rifare la stessa cosa per ogni protocollo).
    %                           L'idea è quella che se n prestazioni identiche sono lo stesso giorno avviene un risparmio
    %                           sul consumo di risorsa pari a n-1 prestazioni. Tuttavia ogni protocollo ha soddisfatto
    %                           la richiesta di prestazione con uno schedule in quel giorno
    %                           Calcolo prima quante prestazioni identiche sono allineate per paziente in un giorno G, 
    %                           poi il risparmio per tutti i pazienti su una prestazione Srv, e infine unisco tutti 
    %                           i risparmi di prestazioni che consumano lo stesso tipo di risorsa Res.
    %                           Questo risparmio va quindi sommato alla capacità Q quando impongo il vincolo di consumo.
%n_prest_allineate(Pat, Srv, G, N) :- patient(Pat), service(Srv, _, _, _), schedule(Pat, Pi, It, Pk, O, G), service_in_packet(Pat, Pi, It, Pk, Srv),  %% così funziona
%                                       N=#count{((Prot, Iter, Pkt), Occ) : schedule(Pat, ((Prot, Iter, Pkt), Occ), G), service_in_packet(Pat, (Prot, Iter, Pkt), Srv)}.

%risparmio_consumo_pr(Srv, Day, Q) :- horizon(Day), service(Srv, _, Quant, _), Sum_Pr=#sum{N-1, Pat : n_prest_allineate(Pat, Srv, Day, N)},
%                                          Q=Sum_Pr*Quant.

%risparmio_consumo_res(Res, Day, Q) :- horizon(Day), care_unit(Res), Q=#sum{Quant, Pr : risparmio_consumo_pr(Pr, Day, Quant), service(Pr, Res, _, _)}.


% GENERATE
    %%% -- SCHEDULE:            Genero uno schedule per ogni occorrenza nel passato, 
    %                           tale che stia nel suo periodo di packet_tolerance.
    %                           Fisso lo schedule per ogni occorrenza la cui data ideale
    %                           sia nel passato, altrimenti immagino sia da schedulare poi o provvisoria.
    %                           NOTA: col rolling horizon e la possibilità di ritoccare alcuni schedule
    %                           l'ultima parte della finestra precedente può essere rivista all'inizio 
    %                           dell'esecuzione successiva per quegli schedule etichettati come provvisori.
0{schedule(Pat, Pkt, Day) : within_tolerance(Pat, Pkt, Day)}1 :-        
     occurrence_to_schedule(Pat, Pkt),                     
     ideal_date(Pat, Pkt, D), D<=0.                                                                                     
                                                                                                                                                                                        
    %%% -- SCHEDULE PROVVISORIO: etichetta per quegli schedule che possono essere rivisti, quinid dal giorno 1
0{temp_schedule(Pat, Pkt, Day) : within_tolerance(Pat, Pkt, Day)}1 :-        
     occurrence_to_schedule(Pat, Pkt),                    
     ideal_date(Pat, Pkt, D), D>0, D<overlap.    

scheduled(Pat, Pkt, G) :- schedule(Pat,Pkt,G).
scheduled(Pat, Pkt, G) :- temp_schedule(Pat,Pkt,G).

%### Debug #########################################################################################################################################
%not_scheduled(Pat, (Pkt_ID, Occ)) :- occurrence_to_schedule(Pat, (Pkt_ID, Occ)), 
%                                                              not scheduled(Pat, (Pkt_ID, Occ), _),
%                                                              ideal_date(Pat, (Pkt_ID, Occ), D), D<overlap.
%n_not_scheduled(N) :- N=#count{P,Pi,Pk,Oc : not_scheduled(P,Pi,Pk,Oc)}.
%###################################################################################################################################################


%CONSTRAINTS
    %%% -- OGNI OCCORRENZA SCHEDULATA:  Weak constraint per massimizzare il numero di occorrenze schedulate al fine di 
    %                                   rispettare sempre tutti i vincoli di integrità
:~ occurrence_to_schedule(Pat, Pkt), not scheduled(Pat, Pkt, _),
     ideal_date(Pat, Pkt, D), D<overlap. [not_scheduled_w,Pat,Pkt]

    %%% -- CAPACITA':           per ogni giorno la somma dei consumi di risorse non DEVE SUPERARE la capacità offerta in quel giorno
%:- horizon(Day), care_unit(CU), #sum{N,Pat,Prot,Iter,Pkt,Occ : scheduled(Pat, (Pkt_ID, Occ), Day), 
%    service_in_packet(Pat, Pkt_ID, Srv), service(Srv, CU, N, _)}>Q+Extra, capacity(Day, CU, Q), risparmio_consumo_res(CU, Day, Extra).
:- horizon(Day), care_unit(CU), 
    #sum{N,Pat,Srv : schedule(Pat, (Pkt_ID, Occ), Day),
    service_in_packet(Pat, Pkt_ID, Srv), 
    service(Srv, CU, N, _)}>Q, 
    capacity(Day, CU, Q).

    %%% -- INCOMPATIBILITA':    la distanza tra 2 occorrenze di pacchetti dello stesso paziente che prevedono 
    %                           prestazioni incompatibili tra loro sia maggiore del tau di incompatibilità
:- scheduled(Pat, (Pkt_ID1, Occ1), Day1), scheduled(Pat, (Pkt_ID2, Occ2), Day2),
    service_in_packet(Pat, Pkt_ID1, Srv1), service_in_packet(Pat, Pkt_ID2, Srv2),
    interdiction(Srv1, Srv2, Tau), Day2 - Day1>=0, Tau>0, Day2 <= Day1+Tau. 
                                                            %notare >0 senza = 
                                                            % se A incomp B, ma non B,A, ammetto che possano 
                                                            % essere lo stesso giorno, ma dovranno essere in ordine B,A
%:- schedule(Pat, Prot1, Iter1, Pkt1_in_P, Occ1, Day), schedule(Pat, Prot2, Iter2, Pkt2_in_P, Occ2, Day),
%    service_in_packet(Pat, Prot1, Iter1, Pkt1_in_P, Srv1), service_in_packet(Pat, Prot2, Iter2, Pkt2_in_P, Srv2),
%    interdiction(Srv1, Srv2, Tau), interdiction(Srv2, Srv1, Tau), Tau>0. %notare Day=Day 
                                                            % se A incomp B, e anche B incomp A, non ammetto che possano 
                                                            % essere lo stesso giorno

    %%% -- NECESSITA':          la distanza tra 2 schedule dello stesso paziente per pacchetti 
    %                           che prevedono prestazioni necessarie consecutive sia rispettata 
    %                           e la seconda cada nella finestra corretta
satisfied_necessity(Pat, (Pkt_IDA, OccA), SrvA, SrvB) :- service_in_packet(Pat, Pkt_IDA, SrvA),  %%%NOTA: NON dice che ha controparte per *TUTTE* le necessità di una service!
                                    necessity(SrvA, SrvB, (Tau_min, Tau_max)), scheduled(Pat, (Pkt_IDA, OccA), DayA),
                                    scheduled(Pat, (Pkt_IDB, OccB), DayB), service_in_packet(Pat, Pkt_IDB, SrvB),
                                    DayB >= DayA+Tau_min, DayB <= DayA+Tau_max.
    %                           Quando il pacchetto si trova alla fine dell'orizzonte temporale, potrebbe essere che il pacchetto necessario 
    %                           sia previsto oltre l'orizzonte, quindi mi accontento e lo accetto comunque
necessity_beyond_horizon(Pat, (Pkt_IDA, OccA), SrvA, SrvB) :- occurrence_to_schedule(Pat, (Pkt_IDA, OccA)), service_in_packet(Pat, Pkt_IDA, SrvA),
                                    necessity(SrvA, SrvB, (Tau_min, Tau_max)), scheduled(Pat, (Pkt_IDA, OccA), DayA),
                                    DayA+Tau_max>=overlap, not satisfied_necessity(Pat, (Pkt_IDA, OccA), SrvA, SrvB).

    %                           non può non essere presente un pacchetto la cui necessità non è soddisfatta o che non può essere soddisfatto 
    %                           da un pacchetto al di fuori dell'orizzonte
:- scheduled(Pat, (Pkt_ID1, Occ1), Day1), service_in_packet(Pat, Pkt_ID1, Srv1),
    necessity(Srv1, Srv2, _), not satisfied_necessity(Pat, (Pkt_ID1, Occ1), Srv1, Srv2), not necessity_beyond_horizon(Pat, (Pkt_ID1, Occ1), Srv1, Srv2).
    
    %                           inoltre entro il tau_min, inizio della finestra di necessità, non è concessa alcuna occorrenza 
    %                           che preveda quel tipo di prestazione necessaria (simile all'incompatibilità)
:- scheduled(Pat, (Pkt_ID1, Occ1), Day1), scheduled(Pat,(Pkt_ID2, Occ2), Day2),
    service_in_packet(Pat, Pkt_ID1, Srv1), service_in_packet(Pat, Pkt_ID2, Srv2),
    necessity(Srv1, Srv2, (Tau_min, _)), Day2 - Day1>=0, Day2 < Day1+Tau_min.

%GENERATE:                      intervallo di variabilità ammessa per ogni schedule provvisorio; il predicato riporta min e max
variability(Pat, Pkt, Day-1, Day+1) :- temp_schedule(Pat, Pkt, Day), Day<overlap/2.
variability(Pat, Pkt, Day-2, Day+2) :- temp_schedule(Pat, Pkt, Day), Day>=overlap/2.


#show schedule/3.
#show temp_schedule/3.
#show variability/4.