import os
import sys
import json
import time
import argparse
import subprocess

from pyomo.environ import ConcreteModel, SolverFactory, maximize
from pyomo.environ import Set, Var, Objective, Constraint
from pyomo.environ import Boolean, value, TerminationCondition, NonNegativeIntegers

######################## INITIAL FILE AND FOLDER SETUP #########################

# read the command line arguments
parser = argparse.ArgumentParser(description="Solve the subproblem")
parser.add_argument("--input", help="folder with the instance file", type=str)
parser.add_argument("-m", "--method", help="solving method", choices=["asp", "milp_basic", "milp_optimized", "milp_epsilon"], default="asp")
parser.add_argument("-t", "--time-limit", help="time limit for the solver", type=int, metavar="T", default=5)
parser.add_argument("-v", "--verbose", help="prints what is done", action="store_true")
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

def solve_with_asp(mashp_input, requests):
    scheduled_services = dict()

    # solve each day separately
    for day_name, day_requests in requests.items():

        # select only the service and packet names actually requested in this day
        packet_names = set()
        for request in day_requests.values():
            packet_names.update(request["packets"])
        service_names = set()
        for packet_name in packet_names:
            service_names.update(mashp_input["abstract_packet"][packet_name])

        # creation of the input file for the asp solver
        with open(config["temporary_asp_file_name"], "w") as file:

            max_time = 0
            for care_unit_name, operators in mashp_input["daily_capacity"][day_name].items():
                for operator_name, operator in operators.items():
                    file.write(f'operator({operator_name}, {care_unit_name}, {operator["start"]}, {operator["duration"]}).\n')
                    if operator["start"] + operator["duration"] > max_time:
                        max_time = operator["start"] + operator["duration"]
            
            file.write(f'time(1..{max_time}).\n')

            for service_name in service_names:
                file.write(f'service({service_name}, {mashp_input["services"][service_name]["careUnit"]}, {mashp_input["services"][service_name]["duration"]}).\n')

            for packet_name in packet_names:
                for service_name in mashp_input["abstract_packet"][packet_name]:
                    file.write(f'packet_has_service({packet_name}, {service_name}).\n')
            
            for patient_name in day_requests.keys():
                file.write(f'patient_has_priority({patient_name}, {mashp_input["pat_request"][patient_name]["priority_weight"]}).\n')
            
            for patient_name, patient in day_requests.items():
                for packet_name in patient["packets"]:
                    file.write(f'patient_requests_packet({patient_name}, {packet_name}).\n')
        
        # solving of the instance
        params = [
            "clingo",
            config["temporary_asp_file_name"],
            os.path.join(config["asp_programs_folder"], config["subproblem_asp_program"]),
            "--time-limit", str(args.time_limit),
            "--verbose=0"
        ]
        with open(config["temporary_output_file_name"], "w") as file:
            subprocess.run(params, stdout=file)
    
        # decoding of the output
        scheduled_services[day_name] = list()
        with open(config["temporary_output_file_name"], "r") as file:

            tokens = file.read().split("\n")[-4].split("do(")[1:]
            tokens[-1] = tokens[-1] + " "
            
            for token in tokens:
                patient_name, service_name, operator_name, care_unit_name, time = token[:-2].split(",")
                scheduled_services[day_name].append({
                    "patient": patient_name,
                    "service": service_name,
                    "operator": operator_name,
                    "careUnit": care_unit_name,
                    "start": int(time),
                })
        
        # removal of temporary working files
        if os.path.isfile(config["temporary_asp_file_name"]):
            os.remove(config["temporary_asp_file_name"])
        if os.path.isfile(config["temporary_output_file_name"]):
            os.remove(config["temporary_output_file_name"])

    return scheduled_services

################################## MILP SOLVER #################################

def solve_with_milp(mashp_input, requests):
    scheduled_services = dict()

    # solve each day separately
    for day_name, day_requests in requests.items():
        scheduled_services[day_name] = list()

        if len(day_requests) == 0:
            continue

        # accumulators for each necessary index (no useless info)
        x_indexes = set()
        chi_indexes = set()
        packet_indexes = set()
        packet_consistency_indexes = set()
        aux1_indexes = set()
        aux2_indexes = set()

        # find the maximum end time for each care unit
        max_times = dict()
        for care_unit_name, care_unit in mashp_input["daily_capacity"][day_name].items():
            max_time = 0
            for operator in care_unit.values():
                end_time = operator["start"] + operator["duration"]
                if end_time > max_time:
                    max_time = end_time
            max_times[care_unit_name] = max_time

        for patient_name, patient in day_requests.items():
            for packet_name in patient["packets"]:
                is_packet_satisfiable = True
                temp_x_indexes = set()
                temp_chi_indexes = set()
                for service_name in mashp_input["abstract_packet"][packet_name]:
                    is_service_satisfiable = False
                    care_unit_name = mashp_input["services"][service_name]["careUnit"]
                    service_duration = mashp_input["services"][service_name]["duration"]
                    for operator_name, operator in mashp_input["daily_capacity"][day_name][care_unit_name].items():
                        if service_duration <= operator["duration"]:
                            is_service_satisfiable = True
                            temp_chi_indexes.add((patient_name, service_name, f"{operator_name}__{care_unit_name}"))
                    if not is_service_satisfiable:
                        is_packet_satisfiable = False
                        break
                    temp_x_indexes.add((patient_name, service_name))
                if is_packet_satisfiable:
                    x_indexes.update(temp_x_indexes)
                    chi_indexes.update(temp_chi_indexes)
                    packet_indexes.add((patient_name, packet_name))
        
        if len(packet_indexes) == 0:
            continue

        for packet_index in packet_indexes:
            for service_name in mashp_input["abstract_packet"][packet_index[1]]:
                packet_consistency_indexes.add((packet_index[0], packet_index[1], service_name))
        
        x_indexes = sorted(x_indexes)
        chi_indexes = sorted(chi_indexes)
        packet_indexes = sorted(packet_indexes)
        packet_consistency_indexes = sorted(packet_consistency_indexes)

        for index1 in range(len(x_indexes) - 1):
            for index2 in range(index1 + 1, len(x_indexes)):
                if x_indexes[index1][0] == x_indexes[index2][0]:
                    aux1_indexes.add((x_indexes[index1][0], x_indexes[index1][1], x_indexes[index2][1]))
        
        for index1 in range(len(chi_indexes) - 1):
            for index2 in range(index1 + 1, len(chi_indexes)):
                if chi_indexes[index1][2] == chi_indexes[index2][2]:
                    if args.method == "milp_basic" or args.method == "milp_epsilon":
                        aux2_indexes.add((chi_indexes[index1][2], chi_indexes[index1][0], chi_indexes[index1][1], chi_indexes[index2][0], chi_indexes[index2][1]))
                    elif args.method == "milp_optimized":
                        aux2_indexes.add((chi_indexes[index1][2], chi_indexes[index1][0], chi_indexes[index1][1], chi_indexes[index2][0], chi_indexes[index2][1], 0))
                        aux2_indexes.add((chi_indexes[index1][2], chi_indexes[index1][0], chi_indexes[index1][1], chi_indexes[index2][0], chi_indexes[index2][1], 1))

        aux1_indexes = sorted(aux1_indexes)
        aux2_indexes = sorted(aux2_indexes)

        # solve subproblem problem
        model = ConcreteModel()

        model.x_indexes = Set(initialize=x_indexes)
        model.chi_indexes = Set(initialize=chi_indexes)
        model.packet_indexes = Set(initialize=packet_indexes)
        model.packet_consistency_indexes = Set(initialize=packet_consistency_indexes)
        model.aux1_indexes = Set(initialize=aux1_indexes)
        model.aux2_indexes = Set(initialize=aux2_indexes)

        del x_indexes, chi_indexes, packet_indexes, packet_consistency_indexes, aux1_indexes, aux2_indexes

        model.x = Var(model.x_indexes, domain=Boolean)
        model.t = Var(model.x_indexes, domain=NonNegativeIntegers)
        model.chi = Var(model.chi_indexes, domain=Boolean)
        model.packet = Var(model.packet_indexes, domain=Boolean)
        model.aux1 = Var(model.aux1_indexes, domain=Boolean)
        model.aux2 = Var(model.aux2_indexes, domain=Boolean)

        if args.method == "milp_epsilon":
            model.epsilon1 = Var(model.aux2_indexes, domain=Boolean)
            model.epsilon2 = Var(model.aux2_indexes, domain=Boolean)

        def f(model):
            return sum(model.packet[patient_name, packet_name] * mashp_input["pat_request"][patient_name]["priority_weight"] for patient_name, packet_name in model.packet_indexes)
        model.objective = Objective(rule=f, sense=maximize)

        def f1(model, patient_name, service_name):
            return model.t[patient_name, service_name] <= model.x[patient_name, service_name] * max_times[mashp_input["services"][service_name]["careUnit"]]
        model.t_and_x = Constraint(model.x_indexes, rule=f1)

        def f2(model, patient_name, service_name):
            return model.t[patient_name, service_name] >= model.x[patient_name, service_name]
        model.x_and_t = Constraint(model.x_indexes, rule=f2)

        def f3(model, patient_name, service_name):
            return sum(model.chi[p, s, o] for p, s, o in model.chi_indexes if patient_name == p and service_name == s) == model.x[patient_name, service_name]
        model.x_and_chi = Constraint(model.x_indexes, rule=f3)

        def f4(model, patient_name, service_name, compound_name):
            operator_name, care_unit_name = compound_name.split("__")
            start = mashp_input["daily_capacity"][day_name][care_unit_name][operator_name]["start"]
            return start * model.chi[patient_name, service_name, compound_name] <= model.t[patient_name, service_name]
        model.respect_start = Constraint(model.chi_indexes, rule=f4)

        def f5(model, patient_name, service_name, compound_name):
            operator_name, care_unit_name = compound_name.split("__")
            start = mashp_input["daily_capacity"][day_name][care_unit_name][operator_name]["start"]
            end = start + mashp_input["daily_capacity"][day_name][care_unit_name][operator_name]["duration"]
            service_duration = mashp_input["services"][service_name]["duration"]
            return model.t[patient_name, service_name] <= (end - service_duration) + (1 - model.chi[patient_name, service_name, compound_name]) * max_times[care_unit_name]
        model.respect_end = Constraint(model.chi_indexes, rule=f5)

        def f6(model, patient_name, packet_name, service_name):
            return model.packet[patient_name, packet_name] <= model.x[patient_name, service_name]
        model.packet_consistency = Constraint(model.packet_consistency_indexes, rule=f6)

        def f7(model, patient_name, service_name1, service_name2):
            service_duration = mashp_input["services"][service_name1]["duration"]
            return (model.t[patient_name, service_name1] + service_duration * model.x[patient_name, service_name1] <= model.t[patient_name, service_name2] +
                (1 - model.aux1[patient_name, service_name1, service_name2]) * max_times[mashp_input["services"][service_name1]["careUnit"]])
        model.patient_not_overlaps1 = Constraint(model.aux1_indexes, rule=f7)

        def f8(model, patient_name, service_name1, service_name2):
            service_duration = mashp_input["services"][service_name2]["duration"]
            return (model.t[patient_name, service_name2] + service_duration * model.x[patient_name, service_name2] <= model.t[patient_name, service_name1] +
                model.aux1[patient_name, service_name1, service_name2] * max_times[mashp_input["services"][service_name2]["careUnit"]])
        model.patient_not_overlaps2 = Constraint(model.aux1_indexes, rule=f8)

        if args.method == "milp_basic":
            def f9(model, operator_name, patient_name1, service_name1, patient_name2, service_name2):
                service_duration = mashp_input["services"][service_name1]["duration"]
                _, care_unit_name = operator_name.split("__")
                return (model.t[patient_name1, service_name1] + service_duration * model.chi[patient_name1, service_name1, operator_name] <= model.t[patient_name2, service_name2] +
                    (1 - model.aux2[operator_name, patient_name1, service_name1, patient_name2, service_name2]) * max_times[care_unit_name])
            model.operator_not_overlaps1 = Constraint(model.aux2_indexes, rule=f9)

            def f10(model, operator_name, patient_name1, service_name1, patient_name2, service_name2):
                service_duration = mashp_input["services"][service_name2]["duration"]
                _, care_unit_name = operator_name.split("__")
                return (model.t[patient_name2, service_name2] + service_duration * model.chi[patient_name2, service_name2, operator_name] <= model.t[patient_name1, service_name1] +
                    model.aux2[operator_name, patient_name1, service_name1, patient_name2, service_name2] * max_times[care_unit_name])
            model.operator_not_overlaps2 = Constraint(model.aux2_indexes, rule=f10)
        elif args.method == "milp_optimized":
            def f9(model, operator_name, patient_name1, service_name1, patient_name2, service_name2, n):
                if n != 0: return Constraint.Skip
                service_duration = mashp_input["services"][service_name1]["duration"]
                _, care_unit_name = operator_name.split("__")
                return (model.t[patient_name1, service_name1] + service_duration * model.chi[patient_name1, service_name1, operator_name] <= model.t[patient_name2, service_name2] +
                    (1 - model.aux2[operator_name, patient_name1, service_name1, patient_name2, service_name2, 0]) * max_times[care_unit_name])
            model.operator_not_overlaps1 = Constraint(model.aux2_indexes, rule=f9)

            def f10(model, operator_name, patient_name1, service_name1, patient_name2, service_name2, n):
                if n != 1: return Constraint.Skip
                service_duration = mashp_input["services"][service_name2]["duration"]
                _, care_unit_name = operator_name.split("__")
                return (model.t[patient_name2, service_name2] + service_duration * model.chi[patient_name2, service_name2, operator_name] <= model.t[patient_name1, service_name1] +
                    model.aux2[operator_name, patient_name1, service_name1, patient_name2, service_name2, 1] * max_times[care_unit_name])
            model.operator_not_overlaps2 = Constraint(model.aux2_indexes, rule=f10)

            def f11(model, operator_name, patient_name1, service_name1, patient_name2, service_name2, n):
                if n != 0: return Constraint.Skip
                return (model.chi[patient_name1, service_name1, operator_name] + model.chi[patient_name2, service_name2, operator_name] - 1 <=
                    model.aux2[operator_name, patient_name1, service_name1, patient_name2, service_name2, 0] + model.aux2[operator_name, patient_name1, service_name1, patient_name2, service_name2, 1])
            model.aux_constraints1 = Constraint(model.aux2_indexes, rule=f11)

            def f12(model, operator_name, patient_name1, service_name1, patient_name2, service_name2, n):
                if n == 1:
                    return (model.chi[patient_name1, service_name1, operator_name] >=
                        model.aux2[operator_name, patient_name1, service_name1, patient_name2, service_name2, 0] + model.aux2[operator_name, patient_name1, service_name1, patient_name2, service_name2, 1])
                return (model.chi[patient_name2, service_name2, operator_name] >=
                    model.aux2[operator_name, patient_name1, service_name1, patient_name2, service_name2, 0] + model.aux2[operator_name, patient_name1, service_name1, patient_name2, service_name2, 1])
            model.aux_constraints2 = Constraint(model.aux2_indexes, rule=f12)
        elif args.method == "milp_epsilon":
            def f9(model, operator_name, patient_name1, service_name1, patient_name2, service_name2):
                service_duration = mashp_input["services"][service_name1]['duration']
                _, care_unit_name = operator_name.split("__")
                return (model.t[patient_name1, service_name1] +
                    service_duration * (model.chi[patient_name1, service_name1, operator_name] - model.epsilon1[operator_name, patient_name1, service_name1, patient_name2, service_name2]) <=
                    model.t[patient_name2, service_name2] +
                    (1 - model.aux2[operator_name, patient_name1, service_name1, patient_name2, service_name2]) * max_times[care_unit_name])
            model.operator_not_overlaps1 = Constraint(model.aux2_indexes, rule=f9)

            def f10(model, operator_name, patient_name1, service_name1, patient_name2, service_name2):
                service_duration = mashp_input["services"][service_name2]['duration']
                _, care_unit_name = operator_name.split("__")
                return (model.t[patient_name2, service_name2] +
                    service_duration * (model.chi[patient_name1, service_name1, operator_name] - model.epsilon2[operator_name, patient_name1, service_name1, patient_name2, service_name2]) <=
                    model.t[patient_name1, service_name1] +
                    model.aux2[operator_name, patient_name1, service_name1, patient_name2, service_name2] * max_times[care_unit_name])
            model.operator_not_overlaps2 = Constraint(model.aux2_indexes, rule=f10)

            def f11(model, operator_name, patient_name1, service_name1, patient_name2, service_name2):
                return model.epsilon1[operator_name, patient_name1, service_name1, patient_name2, service_name2] <= model.chi[patient_name1, service_name1, operator_name]
            model.ff1 = Constraint(model.aux2_indexes, rule=f11)

            def f12(model, operator_name, patient_name1, service_name1, patient_name2, service_name2):
                return model.epsilon1[operator_name, patient_name1, service_name1, patient_name2, service_name2] <= 1 - model.chi[patient_name2, service_name2, operator_name]
            model.ff2 = Constraint(model.aux2_indexes, rule=f12)

            def f13(model, operator_name, patient_name1, service_name1, patient_name2, service_name2):
                return model.epsilon1[operator_name, patient_name1, service_name1, patient_name2, service_name2] <= model.x[patient_name2, service_name2]
            model.ff3 = Constraint(model.aux2_indexes, rule=f13)

            def f14(model, operator_name, patient_name1, service_name1, patient_name2, service_name2):
                return model.epsilon2[operator_name, patient_name1, service_name1, patient_name2, service_name2] <= model.chi[patient_name2, service_name2, operator_name]
            model.ff4 = Constraint(model.aux2_indexes, rule=f14)

            def f15(model, operator_name, patient_name1, service_name1, patient_name2, service_name2):
                return model.epsilon2[operator_name, patient_name1, service_name1, patient_name2, service_name2] <= 1 - model.chi[patient_name1, service_name1, operator_name]
            model.ff5 = Constraint(model.aux2_indexes, rule=f15)

            def f16(model, operator_name, patient_name1, service_name1, patient_name2, service_name2):
                return model.epsilon2[operator_name, patient_name1, service_name1, patient_name2, service_name2] <= model.x[patient_name1, service_name1]
            model.ff6 = Constraint(model.aux2_indexes, rule=f16)

        # model.pprint()

        # problem solving
        opt = SolverFactory("glpk")

        # glpk time limit
        opt.options["tmlim"] = args.time_limit

        # gurobi time limit
        # opt.options["TimeLimit"] = args.time_limit

        result = opt.solve(model)

        # decoding solver answer
        if result.solver.termination_condition == TerminationCondition.infeasible:
            continue

        for patient_name, service_name, compound_name in model.chi_indexes:
            if value(model.chi[patient_name, service_name, compound_name]):
                operator_name, care_unit_name = compound_name.split("__")
                scheduled_services[day_name].append({
                    "patient": patient_name,
                    "service": service_name,
                    "operator": operator_name,
                    "care_unit": care_unit_name,
                    "start": int(value(model.t[patient_name, service_name]))
                })
    
    return scheduled_services

##################################### MAIN #####################################

if args.verbose:
    start_time = time.perf_counter()

# read the current instance file
input_file_name = os.path.join(args.input, config["instance_file_name"])
if not os.path.isfile(input_file_name):
    raise FileNotFoundError(f"Instance file {input_file_name} not found")
with open(input_file_name, "r") as file:
    mashp_input = json.load(file)

# read the current requests file
requests_file_name = os.path.join(args.input, config["subproblem_input_file_name"])
if not os.path.isfile(requests_file_name):
    raise FileNotFoundError(f"Instance file {requests_file_name} not found")
with open(requests_file_name, "r") as file:
    requests = json.load(file)

# instance solving
if args.method == "asp":
    scheduled_services = solve_with_asp(mashp_input, requests)
else:
    scheduled_services = solve_with_milp(mashp_input, requests)

results = dict()

# list all packets that are not satisfied in each day
for day_name, day_requests in requests.items():

    not_scheduled_packets = dict()
    for patient_name, patient in day_requests.items():

        for packet_name in patient["packets"]:
            is_packet_satisfied = True

            for service_name in mashp_input["abstract_packet"][packet_name]:
                is_service_done = False

                for scheduled_service in scheduled_services[day_name]:
                    if scheduled_service["patient"] == patient_name and scheduled_service["service"] == service_name:
                        is_service_done = True
                        break

                if not is_service_done:
                    is_packet_satisfied = False
                    break

            if not is_packet_satisfied:
                if patient_name not in not_scheduled_packets:
                    not_scheduled_packets[patient_name] = list()
                not_scheduled_packets[patient_name].append(packet_name)

        if patient_name in not_scheduled_packets:
            not_scheduled_packets[patient_name].sort()
    
    results[day_name] = {
        "scheduledServices": sorted(scheduled_services[day_name], key=lambda r: r["patient"] + r["service"]),
        "notScheduledPackets": not_scheduled_packets
    }

# write results to file
results_file_name = os.path.join(args.input, config["subproblem_result_file_name"])
with open(results_file_name, "w") as file:
    json.dump(results, file, indent=4)

if args.verbose:
    elapsed_time = time.perf_counter() - start_time
    print(f"Subproblem took {elapsed_time} seconds.")