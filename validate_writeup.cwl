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
  - id: project_id
    type: string
  - id: public
    type: boolean?
  - id: admin
    type: string?


arguments:
  - valueFrom: writeup.py
  - valueFrom: $(inputs.submission_id)
    prefix: -s
  - valueFrom: $(inputs.synapse_config.path)
    prefix: -c
  - valueFrom: $(inputs.project_id)
    prefix: -i
  - valueFrom: results.json
    prefix: -r
  - valueFrom: $(inputs.public)
    prefix: -p
  - valueFrom: $(inputs.admin)
    prefix: -a

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
          parser.add_argument("-i", "--project_id", required=True)
          parser.add_argument("-r", "--results", required=True)
          parser.add_argument("-p", "--public", action='store_true')
          parser.add_argument("-a", "--admin")
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
              f"Submission should be a Synapse project, not a {ent_type}.")

          # Validation #2: is the submission a valid Project a.k.a. not challenge wiki?
          if writeup.entityId == args.project_id:
            errors.append("Submission should not be the Challenge site.")
              
          # Validation #2: is the submission public? (optional)
          try:
            if args.public:
              auth_perms = syn.getPermissions(
                writeup.entityId, AUTHENTICATED_USERS)
              public_perms = syn.getPermissions(writeup.entityId)
              if ("READ" not in auth_perms or "DOWNLOAD" not in auth_perms) and \
                "READ" not in public_perms:
                  errors.append("Your project is not publicly available. Visit " +
                  "https://docs.synapse.org/articles/sharing_settings.html for " +
                  "more details.")
            
            # Validation #2.2: is it accessible by an admin?
            if args.admin:
              admin_perms = syn.getPermissions(writeup.entityId, args.admin)
              if "READ" not in admin_perms or "DOWNLOAD" not in admin_perms:
                errors.append(f"Your private project should be shared with {args.admin}. " +
                "Visit https://docs.synapse.org/articles/sharing_settings.html for " +
                "more details.")

          except synapseclient.exceptions.SynapseHTTPError as e:
            if e.response.status_code == 403:
              errors.append("Submission is private; please update its sharing settings.")
            
            else:
              raise e

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
