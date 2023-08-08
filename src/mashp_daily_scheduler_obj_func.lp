
%OPTIMIZE
    %%% -- Maximize the number of satisfied packets
#maximize { 1@Prior,Pat,Pkt_ID : sat_pkt(Pat, Pkt_ID), priority(Pat, Prior) }.
