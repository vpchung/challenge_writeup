#!/usr/bin/env cwl-runner
cwlVersion: v1.0
class: CommandLineTool
baseCommand: python3

hints:
  DockerRequirement:
    dockerPull: sagebionetworks/synapsepythonclient:v2.0.0

inputs:
  - id: submission_id
    type: int
  - id: synapse_config
    type: File


arguments:
  - valueFrom: writeup.py
  - valueFrom: $(inputs.submission_id)
    prefix: -s
  - valueFrom: $(inputs.synapse_config.path)
    prefix: -c
  - valueFrom: results.json
    prefix: -o

requirements:
  - class: InlineJavascriptRequirement
  - class: InitialWorkDirRequirement
    listing:
      - entryname: writeup.py
        entry: |
          import argparse
          import json
          import time
          
          import synapseclient
          from synapseclient import Synapse, Project
          import synapseutils
          
          parser = argparse.ArgumentParser()
          parser.add_argument("-s", "--submission_id", required=True)
          parser.add_argument("-c", "--config", required=True)
          parser.add_argument("-o", "--results", default="results.json")
          args = parser.parse_args()

          syn = Synapse(configPath=args.config)
          syn.login(silent=True)
          
          writeup = syn.getSubmission(args.submission_id)
          name = writeup.name.replace("&", "+").replace("'", "")
          curr_time = int(round(time.time() * 1000))
          new_project = Project(f"Archived {name} {curr_time} {writeup.id} " +
                                f"{writeup.entityId}")
          archive = syn.store(new_project)
          archived = synapseutils.copy(syn, writeup.entityId, archive.id)
          annot = {"archived": archived.get(writeup.entityId)}
          with open(args.results, "w") as out:
            out.write(json.dumps(annot))

outputs:
  - id: results
    type: File
    outputBinding:
      glob: results.json
