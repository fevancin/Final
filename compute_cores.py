import os
import sys
import json
import time
import argparse

######################## INITIAL FILE AND FOLDER SETUP #########################

# read the command line arguments
parser = argparse.ArgumentParser(description="Compute cores")
parser.add_argument("--input", help="folder with the instance file", type=str)
parser.add_argument("--expand-days", action="store_true")
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

########################## CORES COMPUTATION FUNCTION ##########################

def compute_cores(mashp_input, requests, results, subsumptions):

    # every packet touch some care units with its services
    packet_to_care_units = dict()
    for packet_name, packet in mashp_input["abstract_packet"].items():

        care_unit_set = set()
        for service_name in packet:
            care_unit_name = mashp_input["services"][service_name]["careUnit"]
            care_unit_set.add(care_unit_name)
        packet_to_care_units[packet_name] = care_unit_set

    cores = dict()
    core_index = 0

    for day_name, day_results in results.items():
        for patient_name, packets_not_done in day_results["notScheduledPackets"].items():

            # for each packet not done in the subproblem results
            for packet_not_done in packets_not_done:

                #start the search with it
                nodes_to_do = [{
                    "patient": patient_name,
                    "packet": packet_not_done
                }]
                nodes_done = []

                care_units_to_do = []
                care_units_done = []

                while len(nodes_to_do) > 0:

                    current_node = nodes_to_do.pop()
                    nodes_done.append(current_node) # do a node visit

                    # visit all new care units touched by the new packet
                    for care_unit in packet_to_care_units[current_node["packet"]]:
                        if care_unit not in care_units_done and care_unit not in care_units_to_do:
                            care_units_to_do.append(care_unit)

                    while len(care_units_to_do) > 0:

                        current_care_unit = care_units_to_do.pop()
                        care_units_done.append(current_care_unit) # adds to the already-visited care_units

                        for patient_name_to_add, patient_to_add in requests[day_name].items():
                            for packet_name_to_add in patient_to_add["packets"]:

                                if current_care_unit not in packet_to_care_units[packet_name_to_add]:
                                    continue

                                # search only the (patient, packet) actually satisfied
                                if patient_name_to_add in day_results["notScheduledPackets"] and packet_name_to_add in day_results["notScheduledPackets"][patient_name_to_add]:
                                    continue

                                # the search must proceed only if (patient, packet) is not already processed
                                already_done = False

                                # search if already done in nodes_done
                                for node in nodes_done:
                                    if node["patient"] == patient_name_to_add and node["packet"] == packet_name_to_add:
                                        already_done = True
                                        break
                                if already_done:
                                    continue

                                # search if already done in nodes_to_do
                                for node in nodes_to_do:
                                    if node["patient"] == patient_name_to_add and node["packet"] == packet_name_to_add:
                                        already_done = True
                                        break
                                if already_done:
                                    continue

                                # if another done packet affects the care_unit, adds it to the todo list
                                nodes_to_do.append({
                                    "patient": patient_name_to_add,
                                    "packet": packet_name_to_add
                                })

                care_units_done.sort()

                # group the (patient, packet) list by patient
                packet_groupings: dict[str, list[str]] = dict()
                while len(nodes_done) > 0:
                    node = nodes_done.pop()
                    if node["patient"] not in packet_groupings:
                        packet_groupings[node["patient"]] = []
                    packet_groupings[node["patient"]].append(node["packet"])

                # explode each patient grouping revealing the services of his packets
                multipackets = dict()
                for patient_name, packet_grouping in packet_groupings.items():

                    service_set = set()
                    for packet_name in packet_grouping:
                        for service_name in mashp_input["abstract_packet"][packet_name]:
                            service_set.add(service_name)

                    service_list = sorted(service_set)

                    # the multipacket name is the concatenation of its service names
                    multipacket_name = "_".join(service_list)

                    if multipacket_name in multipackets:
                        multipackets[multipacket_name]["times"] += 1 # not repeating of equal multipackets
                        multipackets[multipacket_name]["actual"][patient_name] = packet_grouping
                    else:
                        multipackets[multipacket_name] = {
                            "times": 1,
                            "services": service_list,
                            "actual": {
                                patient_name: packet_grouping
                            }
                        }
                
                core_days = [day_name]
                # adds all days that are lesser than the current one (intersecting each care_unit affected by the core)
                if args.expand_days:
                    for lesser_day_name in mashp_input["daily_capacity"].keys():

                        if lesser_day_name == day_name:
                            continue

                        is_lesser_day = True
                        for care_unit_name in care_units_done:
                            if day_name not in subsumptions[care_unit_name] or lesser_day_name not in subsumptions[care_unit_name][day_name]:
                                is_lesser_day = False
                                break

                        if is_lesser_day:
                            core_days.append(lesser_day_name)

                    core_days.sort()

                cores[f"core{core_index:02}"] = {
                    "days": core_days,
                    "multipackets": multipackets,
                    "affectedCareUnits": care_units_done
                }

                core_index += 1

    return cores

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
result_file_name = os.path.join(args.input, config["subproblem_input_file_name"])
if not os.path.isfile(result_file_name):
    raise FileNotFoundError(f"Requests file {result_file_name} not found")
with open(result_file_name, "r") as file:
    requests = json.load(file)

# read the current results file
result_file_name = os.path.join(args.input, config["subproblem_result_file_name"])
if not os.path.isfile(result_file_name):
    raise FileNotFoundError(f"Results file {result_file_name} not found")
with open(result_file_name, "r") as file:
    results = json.load(file)

# read the current subsumptions file (only if needed)
if args.expand_days:
    result_file_name = os.path.join(args.input, config["subsumptions_file_name"])
    if not os.path.isfile(result_file_name):
        raise FileNotFoundError(f"Subsumptions file {result_file_name} not found")
    with open(result_file_name, "r") as file:
        subsumptions = json.load(file)
else:
    subsumptions = None

cores = compute_cores(mashp_input, requests, results, subsumptions)

# write results to file
results_file_name = os.path.join(args.input, config["cores_file_name"])
with open(results_file_name, "w") as file:
    json.dump(cores, file, indent=4)

if args.verbose:
    elapsed_time = time.perf_counter() - start_time
    print(f"Cores took {elapsed_time} seconds.")