import os
import sys
import json
import time
import argparse
import subprocess

from src.mashp_tools import format_instance_to_ASP, format_SP_input_from_MP_output

from pyomo.environ import ConcreteModel, SolverFactory, maximize
from pyomo.environ import Set, Var, Objective, Constraint, ConstraintList
from pyomo.environ import Boolean, value, TerminationCondition

######################## INITIAL FILE AND FOLDER SETUP #########################

# read the command line arguments
parser = argparse.ArgumentParser(description="Solve the master problem")
parser.add_argument("--input",              help="folder with the instance file", type=str)
parser.add_argument("-m", "--method",       help="solving method", choices=["asp", "milp"], default="asp")
parser.add_argument("-t", "--time-limit",   help="time limit for the solver", type=int, metavar="T", default=5)
parser.add_argument("--use-cores",                                      action="store_true")
parser.add_argument("--expand-core-names",                              action="store_true")
parser.add_argument("-v", "--verbose",      help="prints what is done", action="store_true")
args = parser.parse_args(sys.argv[1:])

# move the current working directory to the file location
os.chdir(os.path.dirname(__file__))

# read the configuration file
if not os.path.isfile(os.path.join("config", "file_names.json")):
    raise FileNotFoundError("Configuration file not found")
with open(os.path.join("config", "file_names.json"), "r") as file:
    config = json.load(file)

# check the existence of the instance folder
if not os.path.isdir(args.input):
    raise FileNotFoundError("Instance folder not found")

################################## ASP SOLVER ##################################

def solve_with_asp(input_file_name):
    """Returns a schedule attempt as a dict of dict of lists (day->patient->packets)"""

    # creation of the input file for the asp solver
    format_instance_to_ASP(input_file_name)
    INPUT_DIR = os.path.dirname(input_file_name)

    # with open(input_file_name, "r") as file:
    #     mashp_input = json.load(file)

    # with open(config["temporary_asp_file_name"], "w") as file:

    #     file.write(f'day(1..{mashp_input["horizon"]}).\n')
    #     file.write(f'interval(0..100).\n')

    #     for day_name, capacities in mashp_input["capacity"].items():
    #         for care_unit_name, capacity in capacities.items():
    #             file.write(f'day_has_capacity({day_name}, {care_unit_name}, {capacity}).\n')
        
    #     for service_name, service in mashp_input["services"].items():
    #         file.write(f'service({service_name}, {service["careUnit"]}, {service["duration"]}).\n')

    #     for service_name, interdictions in mashp_input["interdiction"].items():
    #         for other_service_name, duration in interdictions.items():
    #             if duration > 0:
    #                 file.write(f'interdiction({service_name}, {other_service_name}, {duration}).\n')

    #     for service_name, necessities in mashp_input["necessity"].items():
    #         for other_service_name, interval in necessities.items():
    #             file.write(f'necessity({service_name}, {other_service_name}, {interval[0]}, {interval[1]}).\n')
        
    #     for packet_name, services in mashp_input["abstract_packet"].items():
    #         for service_name in services:
    #             file.write(f'packet_has_service({packet_name}, {service_name}).\n')
        
    #     for patient_name, patient in mashp_input["pat_request"].items():
    #         file.write(f'patient_has_priority({patient_name}, {patient["priority_weight"]}).\n')
        
    #     for patient_name, patient in mashp_input["pat_request"].items():
    #         for protocol_name, protocol in patient.items():
    #             if protocol_name == "priority_weight":
    #                 continue
    #             for iteration_name, iteration in protocol.items():
    #                 protocol_packets = iteration[0]
    #                 initial_shift = iteration[1]
    #                 for protocol_packet in protocol_packets:
    #                     file.write(f'request({patient_name}, {protocol_name}, {iteration_name}, {protocol_packet["packet_id"]}, {protocol_packet["start_date"]}, {protocol_packet["freq"]}, {protocol_packet["tolerance"]}, {protocol_packet["existence"][0]}, {protocol_packet["existence"][1]}, {initial_shift}).\n')
    
    if args.use_cores:
        with open(config["previous_cores_asp_file_name"], "a+") as file:
            coreid = 0
            if not args.expand_core_names:
                if os.path.isfile("prev_cores.json"):

                    with open("prev_cores.json", "r") as f:
                        prev_cores = json.load(f)

                    for coreid, core in enumerate(prev_cores["list"]):
                        for index, t in enumerate(core):
                            file.write(f"core({t[0]}, {t[1]}, {t[2]}, {coreid}, {index}).")
            
                else:
                    prev_cores = {"list": []}

            if os.path.isfile("cores.json"):

                with open("cores.json", "r") as f:
                    cores = json.load(f)
                
                if args.expand_core_names:
                        for core_name, core in cores.items():
                            coreid += 1
                            for day in core["days"]:
                                current_core = list()
                                for multipacket_name, multipacket in core["multipackets"].items():
                                    for multipacket_index in range(multipacket["times"]):
                                        for service_name in multipacket["services"]:
                                            file.write(f"multipacket_nogood({multipacket_name}, {multipacket_index}, {service_name}, {day}, {multipacket['iteration']}, {core_name})).\n")
                else:
                    for core in cores.values():
                        coreid += 1
                        for day in core["days"]:
                            current_core = list()
                            for multipacket in core["multipackets"].items():
                                for mid, (patient_name, packets) in enumerate(multipacket["actual"].items()):
                                    for packet_name in packets:
                                        file.write(f"core({patient_name}, {packet_name}, {int(day)}, {coreid}, {mid}).")
                                        current_core.append((patient_name, packet_name, day))
                        prev_cores["list"].append(current_core)
                
                os.remove("cores.json")

                if not args.expand_core_names:
                    with open("prev_cores.json", "w") as f:
                        json.dump(prev_cores, f)

    # solving of the instance
    tmp_master_in_file  = os.path.join(INPUT_DIR, config["temporary_asp_file_name"])
    master_asp_file     = os.path.join(config["asp_programs_folder"], config["master_asp_program"])
    tmp_master_out_file = os.path.join(INPUT_DIR, config["temporary_output_file_name"])
    params = [
        "clingo",
        tmp_master_in_file,
        master_asp_file,
        "--time-limit", str(args.time_limit),
        "--verbose=0"
    ]
    with open(tmp_master_out_file, "w") as file:
        subprocess.run(params, stdout=file, stderr=file)#subprocess.DEVNULL)
    
    # decoding of the output
    unordered_results = format_SP_input_from_MP_output(tmp_master_out_file)

    # unordered_results = dict()
    # with open(config["temporary_output_file_name"], "r") as file:

    #     tokens = file.read().split("\n")[-4].split("do(")[1:]
    #     tokens[-1] = tokens[-1] + " "
        
    #     for token in tokens:
    #         patient_name, packet_name, day = token[:-2].split(",")

    #         if day not in unordered_results:
    #             unordered_results[day] = dict()
    #         if patient_name not in unordered_results[day]:
    #             unordered_results[day][patient_name] = {"packets": list()}

    #         unordered_results[day][patient_name]["packets"].append(packet_name)

    # removal of temporary working files
    if os.path.isfile(tmp_master_in_file):
        os.remove(tmp_master_in_file)
    if os.path.isfile(tmp_master_out_file):
        os.remove(tmp_master_out_file)

    # ordering of the keys
    results = dict()
    for day_name in sorted(unordered_results.keys(), key=lambda d: (len(str(d)), d)):
        results[day_name] = unordered_results[day_name]

    return results

################################## MILP SOLVER #################################

def solve_with_milp(input_file_name):
    """Returns a schedule attempt as a dict of dict of lists (day->patient->packets)"""

    with open(input_file_name, "r") as file:
        mashp_input = json.load(file)

    care_units_touched_by_packet = dict()
    for packet_name, packet in mashp_input["abstract_packet"].items():
        care_units = set()
        for service_name in packet:
            care_units.add(mashp_input["services"][service_name]["careUnit"])
        care_units_touched_by_packet[packet_name] = care_units

    x_indexes = set()
    l_indexes = set()
    epsilon_indexes = set()

    x_and_l_indexes = set()
    capacity_indexes = set()
    interdiction_indexes = set()
    necessity_indexes = set()

    for patient_name, patient in mashp_input["pat_request"].items():
        for protocol_name, protocol in patient.items():
            if protocol_name == "priority_weight":
                continue
            for iteration_name, iteration in protocol.items():
                initial_offset = iteration[1]
                for protocol_packet in iteration[0]:
                    packet_name = protocol_packet["packet_id"]
                    for perfect_day in range(protocol_packet["start_date"] + initial_offset, protocol_packet["existence"][1] + initial_offset + 1, protocol_packet["freq"]):
                        if perfect_day < protocol_packet["existence"][0] or perfect_day > protocol_packet["existence"][1]:
                            continue
                        there_is_at_least_one_day = False
                        min_day = 10000
                        max_day = -10000
                        for day_name in range(perfect_day - protocol_packet["tolerance"], perfect_day + protocol_packet["tolerance"] + 1):
                            if day_name >= mashp_input["horizon"] or day_name <= 0:
                                continue
                            if day_name < protocol_packet["existence"][0] or day_name > protocol_packet["existence"][1]:
                                continue
                            is_packet_assignable = True
                            temp_l_indexes = set()
                            for service_name in mashp_input["abstract_packet"][packet_name]:
                                service_care_unit = mashp_input["services"][service_name]["careUnit"]
                                service_duration = mashp_input["services"][service_name]["duration"]
                                if service_duration > mashp_input["capacity"][str(day_name)][service_care_unit]:
                                    is_packet_assignable = False
                                    break
                                temp_l_indexes.add((patient_name, service_name, day_name))
                            if is_packet_assignable:
                                x_indexes.add((patient_name, packet_name, day_name))
                                l_indexes.update(temp_l_indexes)
                                for care_unit_name in care_units_touched_by_packet[packet_name]:
                                    capacity_indexes.add((day_name, care_unit_name))
                                for patient_name1, service_name1, day_name1 in temp_l_indexes:
                                    x_and_l_indexes.add((patient_name1, packet_name, service_name1, day_name1))
                                there_is_at_least_one_day = True
                                if day_name < min_day:
                                    min_day = day_name
                                if day_name > max_day:
                                    max_day = day_name
                        if there_is_at_least_one_day:
                            epsilon_indexes.add((patient_name, packet_name, f"{protocol_name}__{iteration_name}__{min_day}__{max_day}"))

    for service_name1, necessities in mashp_input["necessity"].items():
        for service_name2, times in necessities.items():
            if times[0] - 1 > mashp_input["interdiction"][service_name1][service_name2]:
                mashp_input["interdiction"][service_name1][service_name2] = times[0] - 1
            for patient_name3, service_name3, day_name3 in l_indexes:
                    for patient_name4, service_name4, _ in l_indexes:
                        if service_name3 == service_name1 and patient_name3 == patient_name4 and service_name4 == service_name2:
                            necessity_indexes.add((patient_name3, service_name1, service_name2, day_name3))

    for service_name1, interdictions in mashp_input["interdiction"].items():
        for service_name2, time in interdictions.items():
            if time > 0:
                for patient_name3, service_name3, day_name3 in l_indexes:
                    for patient_name4, service_name4, _ in l_indexes:
                        if service_name3 == service_name1 and patient_name3 == patient_name4 and service_name4 == service_name2:
                            interdiction_indexes.add((patient_name3, service_name1, service_name2, day_name3))

    x_indexes = sorted(x_indexes)
    l_indexes = sorted(l_indexes)
    epsilon_indexes = sorted(epsilon_indexes)
    x_and_l_indexes = sorted(x_and_l_indexes)
    capacity_indexes = sorted(capacity_indexes)
    interdiction_indexes = sorted(interdiction_indexes)
    necessity_indexes = sorted(necessity_indexes)

    model = ConcreteModel()

    model.x_indexes = Set(initialize=x_indexes)
    model.l_indexes = Set(initialize=l_indexes)
    model.epsilon_indexes = Set(initialize=epsilon_indexes)
    model.x_and_l_indexes = Set(initialize=x_and_l_indexes)
    model.capacity_indexes = Set(initialize=capacity_indexes)
    model.interdiction_indexes = Set(initialize=interdiction_indexes)
    model.necessity_indexes = Set(initialize=necessity_indexes)

    del x_indexes, l_indexes, epsilon_indexes, x_and_l_indexes, capacity_indexes, interdiction_indexes, necessity_indexes

    model.x = Var(model.x_indexes, domain=Boolean)
    model.l = Var(model.l_indexes, domain=Boolean)
    model.epsilon = Var(model.epsilon_indexes, domain=Boolean)

    def ff(model):
        return sum(model.epsilon[patient_name, packet_name, window_name] for patient_name, packet_name, window_name in model.epsilon_indexes)
    model.objective = Objective(rule=ff, sense=maximize)

    def f1(model, patient_name, packet_name, service_name, day_name):
        return model.x[patient_name, packet_name, day_name] <= model.l[patient_name, service_name, day_name]
    model.x_and_l = Constraint(model.x_and_l_indexes, rule=f1)

    def f2(model, patient_name, packet_name, window_name):
        _, _, min_day, max_day = window_name.split("__")
        return sum([model.x[patient_name, packet_name, day_name] for day_name in range(int(min_day), int(max_day) + 1) if (patient_name, packet_name, day_name) in model.x]) == model.epsilon[patient_name, packet_name, window_name]
    model.x_and_epsilon = Constraint(model.epsilon_indexes, rule=f2)

    def f3(model, day_name, care_unit_name):
        return (sum([model.l[patient_name, service_name, day_name] * mashp_input["services"][service_name]["duration"]
            for patient_name, service_name, day_name1 in model.l_indexes
            if day_name1 == day_name and mashp_input["services"][service_name]["careUnit"] == care_unit_name]) <=
            mashp_input["capacity"][str(day_name)][care_unit_name])
    model.respect_capacity = Constraint(model.capacity_indexes, rule=f3)

    def f4(model, patient_name, service_name1, service_name2, day_name):
        time = mashp_input["interdiction"][service_name1][service_name2]
        day_names = list()
        for day_name2 in range(day_name + 1, day_name + time + 1):
            if (patient_name, service_name2, day_name2) in model.l:
                day_names.append(day_name2)
        if len(day_names) == 0:
            return Constraint.Skip
        return sum([model.l[patient_name, service_name2, day_name2] for day_name2 in day_names]) <= (1 - model.l[patient_name, service_name1, day_name]) * len(day_names)
    model.interdictions = Constraint(model.interdiction_indexes, rule=f4)

    impossible_assignments = set()

    def f5(model, patient_name, service_name1, service_name2, day_name):
        times = mashp_input["necessity"][service_name1][service_name2]
        day_names = list()
        for day_name2 in range(day_name + times[0], day_name + times[1] + 1):
            if (patient_name, service_name2, day_name2) in model.l:
                day_names.append(day_name2)
        if len(day_names) == 0:
            impossible_assignments.add((patient_name, service_name1, day_name))
            return Constraint.Skip
        return sum([model.l[patient_name, service_name2, day_name2] for day_name2 in day_names]) >= model.l[patient_name, service_name1, day_name]
    model.necessities = Constraint(model.necessity_indexes, rule=f5)

    for patient_name, service_name, day_name in impossible_assignments:
        model.l[patient_name, service_name, day_name].fix(0)
        for patient_name1, packet_name, day_name1 in model.x_indexes:
            if patient_name1 == patient_name and day_name1 == day_name and service_name in mashp_input["abstract_packet"][packet_name]:
                model.x[patient_name, packet_name, day_name].fix(0)

    if args.use_cores:

        model.core_constraints = ConstraintList()

        # add previous core constraints if present
        if os.path.isfile("prev_cores.json"):

            with open("prev_cores.json", "r") as f:
                prev_cores = json.load(f)

            # for each previous tuple
            for prev_core in prev_cores["list"]:

                # read its indexes
                indexes = []
                for core_constraint in prev_core:
                    indexes.append((core_constraint[0], core_constraint[1], core_constraint[2]))

                # add the impossibility constraint on its indexes
                model.core_constraints.add(expr=sum(model.l[p, s, int(d)] for (p, s, d) in indexes) <= len(indexes) - 1)

        else:
            # create the empty core list
            prev_cores = {"list": []}

        # if there is a core file add its constraints
        if os.path.isfile("cores.json"):

            with open("cores.json", "r") as f:
                cores = json.load(f)

            for core in cores.values():
                for day_name in core["days"]:

                    # create a dict patient->services of all the requests of this day
                    patient_services = dict()
                    for patient_name, packet_name, day_name in x_indexes:

                        # test only the values of the right days
                        if day_name != int(day_name):
                            continue

                        if patient_name not in patient_services:
                            patient_services[patient_name] = set()

                        # adds all the packet services
                        for service_name in mashp_input["abstract_packet"][packet_name]:
                            patient_services[patient_name].add(service_name)

                    for patient_name, service_list in patient_services.items():
                        patient_services[patient_name] = sorted(service_list)
                    
                    who_could_be = []
                    total_durations: dict[str, int] = dict()
                    for multipacket_name, multipacket in core["multipackets"].items():
                        patient_list = []
                        for patient_name, service_list in patient_services.items():
                            is_contained = True
                            for service_name in multipacket["services"]:
                                care_unit_name = mashp_input["services"][service_name]["careUnit"]
                                duration = mashp_input["services"][service_name]["duration"]
                                if care_unit_name not in total_durations:
                                    total_durations[care_unit_name] = 0
                                total_durations[care_unit_name] += duration
                                if service_name not in service_list:
                                    is_contained = False
                                    break
                            if is_contained:
                                patient_list.append(patient_name)
                        who_could_be.append({
                            "name": multipacket_name,
                            "patients": patient_list
                        })
                    # check on care_unit sum, in order to not add something already seen
                    is_day_valid = True
                    for care_unit_name, duration in total_durations.items():
                        if duration > mashp_input["capacity"][day_name][care_unit_name]:
                            is_day_valid = False
                            break
                    if not is_day_valid:
                        continue
                    # who_could_be = [
                    #     {"name": 'srv01_srv05', "patients": ['pat00', 'pat03', 'pat05']},
                    #     {"name": 'srv05', "patients": ['pat00', 'pat01']},
                    #     {"name": 'srv07', "patients": ['pat06', 'pat12', 'pat22']}
                    # ]
                    # print(who_could_be)
                    if args.expand_core_names:
                        choice_indexes = []
                        for _ in who_could_be:
                            choice_indexes.append(0)
                        def get_next(value3: list[int]=None):
                            if value3 is None:
                                return [0 for _ in who_could_be]
                            index = 0
                            while index < len(who_could_be):
                                value3[index] += 1
                                if value3[index] < len(who_could_be[index]["patients"]):
                                    return value3
                                value3[index] = 0
                                index += 1
                            return None
                        value2 = get_next()
                        while value2 is not None:
                            actual_value = []
                            for value_index in range(len(value2)):
                                actual_value.append(who_could_be[value_index]["patients"][value2[value_index]])
                            # check for repetitions...
                            is_valid_value = len(set(actual_value)) == len(actual_value)
                            if is_valid_value:
                                # add index at the day 'day_name' for patients in the index
                                expr_indexes = []
                                core_list = []
                                for index in range(len(actual_value)):
                                    for service_name in core["multipackets"][who_could_be[index]["name"]]["services"]:
                                        expr_indexes.append((actual_value[index], service_name))
                                        core_list.append([actual_value[index], service_name, day_name])
                                model.core_constraints.add(expr=sum(model.l[p, s, int(day_name)] for (p, s) in expr_indexes) <= len(expr_indexes) - 1)
                                prev_cores["list"].append(core_list)
                            value2 = get_next(value2)
                    else:
                        for multipacket in core["multipackets"].values():
                            for patient_name, packet_list in multipacket["actual"]:
                                expr_indexes = set()
                                core_list = []
                                for packet_name in packet_list:
                                    for service_name in mashp_input["abstract_packet"][packet_name]:
                                        expr_indexes.add((patient_name, service_name))
                                for index in expr_indexes:
                                    core_list.append([index[0], index[1], day_name])
                                model.core_constraints.add(expr=sum(model.l[p, s, int(day_name)] for (p, s) in expr_indexes) <= len(expr_indexes) - 1)
                                prev_cores["list"].append(core_list)

            # keep memory of all the cores up until now
            with open("prev_cores.json", "w") as f:
                json.dump(prev_cores, f)

            # remove the cores of the current iteration to not be mistaken the next time
            os.remove("cores.json")

    # glpk (comment if gurobi is used)
    opt = SolverFactory("glpk")
    opt.options["tmlim"] = args.time_limit

    # gurobi (comment if glpk is used)
    # opt = SolverFactory("gurobi")
    # opt.options["TimeLimit"] = args.time_limit

    result = opt.solve(model)

    # model.pprint()

    # decoding of the output
    results = dict()
    if result.solver.termination_condition == TerminationCondition.infeasible:
        results = {}
    else:
        for patient_name, packet_name, day_name in model.x_indexes:

            if value(model.x[patient_name, packet_name, day_name]) == 0:
                continue

            if day_name not in results:
                results[day_name] = dict()
            if patient_name not in results[day_name]:
                results[day_name][patient_name] = {"packets": list()}

            results[day_name][patient_name]["packets"].append(packet_name)
    
    return results

############################### CORE COMPUTATION ###############################
################################# NOT FINISHED #################################

# def process_cores():
#     """Returns a list of list of triplets (patient, service, day).
#     Each sublist correspond to a different impossible assignment."""

#     # read previous cores, if present
#     previous_ground_cores = list()
#     previous_cores_file_name = os.path.join(args.input, config["previous_cores_file_name"])
#     if os.path.isfile(previous_cores_file_name):
#         with open(previous_cores_file_name, "r") as file:
#             temp = json.load(file)
#         previous_ground_cores = temp["list"]
#         del temp

#     # read the core file, if present
#     cores_file_name = os.path.join(args.input, config["cores_file_name"])
#     if not os.path.isfile(cores_file_name):
#         return previous_ground_cores
#     with open(cores_file_name, "r") as file:
#         cores = json.load(file)
#     # os.remove(cores_file_name)
    
#     current_ground_cores = list()
#     for core in cores.values():
#         for day_name in core["days"]:
#             ground_core = list()
#             for multipacket in core["multipacket"].values():
#                 if not args.expand_core_names:
#                     for patient_name, packet_name in multipacket["actual"].items():
#                         ground_core.append((patient_name, packet_name, int(day_name)))
#                     else:
#                         pass

#     # if new cores were found, write them to file for the next iteration
#     if len(current_ground_cores) > 0:
#         current_ground_cores.extend(previous_ground_cores)
#         current_ground_cores = sorted(set(current_ground_cores))
#         with open(previous_cores_file_name, "w") as file:
#             json.dump(current_ground_cores, file)

#     return current_ground_cores

###################################### MAIN ####################################

if args.verbose:
    start_time = time.perf_counter()

# read the current instance file
input_file_name = os.path.join(args.input, config["instance_file_name"])
if not os.path.isfile(input_file_name):
    raise FileNotFoundError(f"Instance file {input_file_name} not found")

# instance solving
if args.method == "asp":
    requests = solve_with_asp(input_file_name)
else:
    requests = solve_with_milp(input_file_name)

# write requests to file
results_file_name = os.path.join(args.input, config["subproblem_input_file_name"])
with open(results_file_name, "w") as file:
    json.dump(requests, file, indent=4)

if args.verbose:
    elapsed_time = time.perf_counter() - start_time
    print(f"Master took {elapsed_time} seconds.")