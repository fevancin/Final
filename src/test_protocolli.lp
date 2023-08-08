%DEF
occurrence_to_schedule(Pkt_in_Prot, Occ) :- 
    packet_instance(Pkt_in_Prot), n_occurrences(Pkt_in_Prot, N_occ), Occ=1..N_occ.

service_in_packet(Pkt, Pr) :- packet_type(Pkt, Tipo), service_in_packet(Tipo, Pr).


min_max_tolerance(Pkt, Occ, Min, Max) :- occurrence_to_schedule(Pkt, Occ), packet_tolerance(Pkt, Tol),
                                                         packet_frequency(Pkt, Freq), packet_start(Pkt, S),
                                                         Min=S+Freq*(Occ-1)-Tol, Max=S+Freq*(Occ-1)+Tol.
within_tolerance(Pkt, Occ, (Min..Max)) :- min_max_tolerance(Pkt, Occ, Min, Max).

%Generate
1{schedule(Pkt, Occ, Day) : horizon(Day), within_tolerance(Pkt, Occ, Day)}1 :-
     occurrence_to_schedule(Pkt, Occ).

%Constraints

    %%% -- INCOMPATIBILITA':    la distanza tra 2 schedule dello stesso paziente per pacchetti 
    %                           che prevedono prestazioni incompatibili sia maggiore del tau di incompatibilità
:- schedule(Pkt1_in_P, Occ1, Day1), schedule(Pkt2_in_P, Occ2, Day2),
    service_in_packet(Pkt1_in_P, Srv1), service_in_packet(Pkt2_in_P, Srv2),
    interdiction(Srv1, Srv2, Tau), Day2 - Day1>=0, Tau>0, Day2 - Day1 <= Tau. %notare >0 senza = 
                                                                    % se A incomp B, ma non B,A, ammetto che possano 
                                                                    % essere lo stesso giorno, ma dovranno essere in ordine B,A
%:- schedule(Pkt1_in_P, Occ1, Day), schedule(Pkt2_in_P, Occ2, Day),
%    service_in_packet(Pkt1_in_P, Srv1), service_in_packet(Pkt2_in_P, Srv2),
%    interdiction(Srv1, Srv2, Tau), interdiction(Srv2, Srv1, Tau), Tau>0. %notare =0 
                                                                    % se A incomp B, e anche B incomp A, non ammetto che possano 
                                                                    % essere lo stesso giorno

    %%% -- NECESSITA':          la distanza tra 2 schedule dello stesso paziente per pacchetti 
    %                           che prevedono prestazioni necessarie consecutive sia rispettata e la seconda cada nella finestra corretta
satisfied_necessity(PacA, OccA, SrvA, SrvB) :- service_in_packet(PacA, SrvA),  %%%NON DICE CHE HA CONTROPARTE PER TUTTE LE NECESSITà DI UNA PREST!
                                    necessity(SrvA, SrvB, (Tau_min, Tau_max)), schedule(PacA, OccA, DayA),
                                    schedule(PacB, OccB, DayB), service_in_packet(PacB, SrvB),
                                    DayB >= DayA+Tau_min, DayB <= DayA+Tau_max.
    %                           Quando il pacchetto si trova alla fine dell'orizzonte temporale, potrebbe essere che il pacchetto necessario 
    %                           sia previsto altro l'orizzonte, quindi mi accontento

:- schedule(Pkt1_in_P, Occ1, Day1), service_in_packet(Pkt1_in_P, Srv1),
    necessity(Srv1, Srv2, _), not satisfied_necessity(Pkt1_in_P, Occ1, Srv1, Srv2).
    
    %                           ENTRO IL TAU_min NON DEVE ESSERCI NESSUNA OCCORRENZA DI QUEL PACCHETTO
:- schedule(Pkt1_in_P, Occ1, Day1), schedule(Pkt2_in_P, Occ2, Day2),
    service_in_packet(Pkt1_in_P, Srv1), service_in_packet(Pkt2_in_P, Srv2),
    necessity(Srv1, Srv2, (Tau_min, _)), Day2 - Day1>=0, Day2 - Day1 < Tau_min.

%#show protocollo_testato/1.
#show schedule/3.