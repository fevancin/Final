import os
import sys
import json
import time
import argparse
import subprocess

######################## INITIAL FILE AND FOLDER SETUP #########################

# move the current working directory to the file location
os.chdir(os.path.dirname(__file__))

# read the configuration file
if not os.path.isfile(os.path.join("config", "file_names.json")):
    raise FileNotFoundError("Configuration file not found")
with open(os.path.join("config", "file_names.json"), "r") as file:
    config = json.load(file)

# read the command line arguments
parser = argparse.ArgumentParser(description="Main script for the instances solving process")
parser.add_argument("--input",              help="input folder with the instances", type=str, metavar="I", default=config["instances_folder"])

parser.add_argument("--master-method",      help="master solving method",       choices=["asp", "milp"], default="asp")
parser.add_argument("--subproblem-method",  help="subproblem solving method",   choices=["asp", "milp_basic", "milp_optimized", "milp_epsilon"], default="milp_optimized")

parser.add_argument("-t", "--time-limit",   help="time limit for the solvers",  type=int, metavar="T", default=3600)
parser.add_argument("--max-iteration",      help="maximum iteration amount",    type=int, metavar="I", default=100000000)

parser.add_argument("--use-cores",          action="store_true")
parser.add_argument("--expand-core-days",   action="store_true")
parser.add_argument("--expand-core-names",  action="store_true")

parser.add_argument("-v", "--verbose",      help="prints what is done", action="store_true")

args = parser.parse_args(sys.argv[1:])


def is_instance_completely_solved(instance_path_name):

    # read the current results file
    input_file_name = os.path.join(instance_path_name, config["subproblem_result_file_name"])
    if not os.path.isfile(input_file_name):
        raise FileNotFoundError(f"Results file {input_file_name} not found")
    with open(input_file_name, "r") as file:
        results = json.load(file)
    
    for day_results in results.values():
        if len(day_results["notScheduledPackets"]) > 0:
            return False

    return True

##################################### MAIN #####################################

# it's useless to do more than one iteration if no cores are used
if args.use_cores:
    max_iteration = args.max_iteration
else:
    max_iteration = 1

if os.path.isfile(config["previous_cores_asp_file_name"]):
    with open(config["previous_cores_asp_file_name"], "w") as file:
        file.write("mpk.\n")

if args.verbose:
    global_start_time = time.perf_counter()
    instance_number = 0
    group_number = 0

# iterate through instance groups
for group_folder_name in sorted(os.listdir(args.input)):

    if args.verbose:
        group_number += 1

    # iterate through instances
    for instance_folder_name in sorted(os.listdir(os.path.join(args.input, group_folder_name))):
        instance_path_name = os.path.join(args.input, group_folder_name, instance_folder_name)

        if args.verbose:
            instance_start_time = time.perf_counter()
            print(f"Starting instance {instance_path_name}")

        # conpute subsumptions only if necessary
        if args.use_cores and args.expand_core_days:
            params = [
                "python", config["subsumption_script"],
                "--input", instance_path_name
            ]
            if args.verbose:
                params.append("-v")
            subprocess.run(params)

        iteration_index = 0
        while iteration_index < max_iteration:

            if args.verbose:
                iteration_start_time = time.perf_counter()
                print(f"Starting iteration {iteration_index}")

            # solve master problem
            params = [
                "python", config["master_problem_script"],
                "--input", instance_path_name,
                "--method", args.master_method,
                "--time-limit", str(args.time_limit)
            ]
            if args.use_cores and args.expand_core_names:
                params.append("--expand-core-names")
            if args.verbose:
                params.append("--verbose")
            subprocess.run(params)

            # solve subproblem
            params = [
                "python", config["subproblem_script"],
                "--input", instance_path_name,
                "--method", args.subproblem_method,
                "--time-limit", str(args.time_limit)
            ]
            if args.verbose:
                params.append("--verbose")
            subprocess.run(params)

            if is_instance_completely_solved(instance_path_name):
                if args.verbose:
                    iteration_elapsed_time = time.perf_counter() - iteration_start_time
                    print(f"Instance completely solved, breaking the iteration cycle. Took {iteration_elapsed_time} seconds.")
                break

            # compute cores if needed
            if args.use_cores:
                params = [
                    "python", config["cores_script"],
                    "--input", instance_path_name,
                    "--iteration", iteration_index
                ]
                if args.expand_core_days:
                    params.append("--expand-days")
                if args.verbose:
                    params.append("--verbose")
                subprocess.run(params)

            if args.verbose:
                iteration_elapsed_time = time.perf_counter() - iteration_start_time
                print(f"Ending iteration {iteration_index}. Took {iteration_elapsed_time} seconds.")
            
            iteration_index += 1
        
        if args.verbose:
            instance_number += 1
            instance_elapsed_time = time.perf_counter() - instance_start_time
            print(f"Ending instance {instance_path_name}. Took {instance_elapsed_time} seconds.\n")

if args.verbose:
    global_elapsed_time = time.perf_counter() - global_start_time
    print(f"Processed {instance_number} instances in {group_number} groups. Total time taken: {global_elapsed_time} seconds.")