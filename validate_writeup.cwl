#!/usr/bin/env cwl-runner
cwlVersion: v1.0
class: CommandLineTool
baseCommand: python3

hints:
  DockerRequirement:
    dockerPull: sagebionetworks/synapsepythonclient:v1.9.2

inputs:
  - id: submission_id
    type: int
  - id: synapse_config
    type: File
  - id: public
    type: boolean?


arguments:
  - valueFrom: writeup.py
  - valueFrom: $(inputs.submission_id)
    prefix: -s
  - valueFrom: $(inputs.synapse_config.path)
    prefix: -c
  - valueFrom: results.json
    prefix: -r
  - valueFrom: $(inputs.public)
    prefix: -p

requirements:
  - class: InlineJavascriptRequirement
  - class: InitialWorkDirRequirement
    listing:
      - entryname: writeup.py
        entry: |
          import argparse
          import json
          import re
          
          import synapseclient
          from synapseclient import AUTHENTICATED_USERS, Synapse
          
          parser = argparse.ArgumentParser()
          parser.add_argument("-s", "--submission_id", required=True)
          parser.add_argument("-c", "--config", required=True)
          parser.add_argument("-r", "--results", required=True)
          parser.add_argument("-p", "--public", action='store_true')
          args = parser.parse_args()
          
          syn = Synapse(configPath=args.config)
          syn.login(silent=True)
          writeup = syn.getSubmission(args.submission_id)
          errors = []
          
          # Validation #1: is the submission a Project?
          if not isinstance(writeup.entity, synapseclient.entity.Project):
            ent_type = re.search(r"entity\.(.*?)'", 
              str(type(writeup.entity))).group(1)
            errors.append(
              f"Please submit a Synapse Project for the writeup, not a {ent_type}.")
              
          # Validation #2: is the submission public? (optional)
          try:
          
            # Validation #2.2: can it be downloaded by Synapse users?
            if args.public:
              auth_perms = syn.getPermissions(
                writeup.entityId, AUTHENTICATED_USERS)
              if "READ" not in auth_perms or "DOWNLOAD" not in auth_perms:
                errors.append(f"Please enable 'Can download' permissions to " +
                               "other Synapse users in your writeup project.")

              public_perms = syn.getPermissions(writeup.entityId)
              if "READ" not in public_perms:
                errors.append(f"Please enable 'Can view' permissions to the " +
                               "public in your writeup project.")

          except synapseclient.exceptions.SynapseHTTPError as e:
            if e.response.status_code == 403:
              errors.append(f"Please make your private writeup public.")

          result = {'writeup_errors': "\n".join(errors),
                    'writeup_status': "INVALID" if errors else "VALIDATED"}
            
          with open(args.results, "w") as out:
            out.write(json.dumps(result))

outputs:
  - id: results
    type: File
    outputBinding:
      glob: results.json

  - id: status
    type: string
    outputBinding:
      glob: results.json
      loadContents: true
      outputEval: $(JSON.parse(self[0].contents)['writeup_status'])

  - id: invalid_reasons
    type: string
    outputBinding:
      glob: results.json
      loadContents: true
      outputEval: $(JSON.parse(self[0].contents)['writeup_errors'])
