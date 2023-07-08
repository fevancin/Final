%%%%%%%%%%%%%%%%%%%%%%% THE INPUT MUST BE IN THE FORM OF: %%%%%%%%%%%%%%%%%%%%%%

% day(1..Horizon).
% interval(0..100).

% day_has_capacity(Day, CareUnit, Capacity).

% service(Service, CareUnit, Duration).
% interdiction(Service1, Service2, Duration).
% necessity(Service1, Service2, Start, End).

% packet_has_service(Packet, Service).

% patient_has_priority(Patient, Priority).
% request(Patient, Protocol, Iteration, Packet,
%    Start, Frequency, Tolerance, ExistenceStart, ExistenceEnd, InitialShift).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% ACTUAL PROGRAM %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% decision variables (if a patient requests a packet to be done in a certain day)
{ do(Patient, Packet, Day) } :-
    request(Patient, _, _, Packet, Start, Frequency, Tolerance, ExistenceStart, ExistenceEnd, InitialShift),
    day(Day),
    Day >= ExistenceStart + InitialShift,
    Day <= ExistenceEnd + InitialShift,
    (Day - (Start + InitialShift) + Tolerance) \ Frequency <= 2 * Tolerance.

% it's impossible to schedule together packets for a total duration bigger than the one provided for that day
:- day_has_capacity(Day, CareUnit, Capacity),
    #sum { ServiceDuration,Patient,Service :
        do(Patient, Packet, Day),
        packet_has_service(Packet, Service),
        service(Service, CareUnit, ServiceDuration)
    } > Capacity.

% interdiction implemementation
:- do(Patient, Packet1, Day1), do(Patient, Packet2, Day2), Day1 != Day2,
    packet_has_service(Packet1, Service1), packet_has_service(Packet2, Service2),
    interdiction(Service1, Service2, Duration),
    Day2 - Day1 <= Duration.

% necessity implementation
:- do(Patient, Packet1, Day1), do(Patient, Packet2, Day2), Day1 != Day2,
    packet_has_service(Packet1, Service1), packet_has_service(Packet2, Service2),
    necessity(Service1, Service2, Start, End),
    Day2 - Day1 <= Start ; Day2 - Day1 >= End.

% intervals describe with an index the ranges (start), (start + frequency), (start + 2*frequency) ...
is_interval(Patient, Protocol, Iteration, Packet, IntervalIndex) :-
    request(Patient, Protocol, Iteration, Packet, Start, Frequency, _, _, ExistenceEnd, _),
    interval(IntervalIndex),
    IntervalIndex <= (ExistenceEnd - Start) / Frequency.

% if an interval is satisfied, it's satisfied only by one do() predicate
:- do(Patient, Packet, Day1), do(Patient, Packet, Day2), Day1 != Day2,
    request(Patient, Protocol, Iteration, Packet, Start, Frequency, Tolerance, ExistenceStart, ExistenceEnd, InitialShift),
    is_interval(Patient, Protocol, Iteration, Packet, IntervalIndex),
    Day1 - (Start + InitialShift + Frequency * IntervalIndex) >= -Tolerance,
    Day1 - (Start + InitialShift + Frequency * IntervalIndex) <= Tolerance,
    Day2 - (Start + InitialShift + Frequency * IntervalIndex) >= -Tolerance,
    Day2 - (Start + InitialShift + Frequency * IntervalIndex) <= Tolerance.

% an interval is satisfied if there is a do() with a day inside its interval
is_interval_satisfied(Patient, Protocol, Iteration, Packet, IntervalIndex) :-
    is_interval(Patient, Protocol, Iteration, Packet, IntervalIndex),
    request(Patient, Protocol, Iteration, Packet, Start, Frequency, Tolerance, _, _, InitialShift),
    do(Patient, Packet, Day),
    Day - (Start + InitialShift + Frequency * IntervalIndex) >= -Tolerance,
    Day - (Start + InitialShift + Frequency * IntervalIndex) <= Tolerance.

% objective constraints, weighted by priority
:~ is_interval_satisfied(Patient, Protocol, Iteration, Packet, IntervalIndex), patient_has_priority(Patient, Priority).
    [-1@Priority,Patient,Protocol,Iteration,Packet,IntervalIndex]

#show do/3.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% DEBUG INFO (IGNORE) %%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% :~ do(Patient, Packet, Day), patient_has_priority(Patient, Priority). [-1@Priority,Patient,Packet,Day]

% #show is_interval/5.
% #show is_interval_satisfied/5.