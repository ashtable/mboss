# Turn a Design and a Plan into Tests and Code

The following prompt is used to turn a set of design documents, implementation plan and optionally an initial mockup specified by the user into a working implementation of code and tests.

## Relevant Skills
- Use the DBOS skill for any work involing DBOS workflows or DBOSClient SDKs
- Use the frontend-design skill for any work on the Next.js UI in mboss-web project, or the Next.js UIs that will be generated/scaffolded by the mBoss VS Code Extension
- Use the playwright mcp server and skill as needed when designing, writing, running tests or verifying functionality 
- Use the chromdevtools mcp server as needed when designing, writing, running tests or verifying functionality 
- Use the react-flow skill whenever working on the react-flow UI within the VS Code extension 
- Use the vscode-ext-commands and vscode-ext-localization skills as needed when building out the vscode extension functionality
- Use the zod skill whenever working on Zod schemas 
- Use the prisma-client, prisma-client-api, prisma-database-setup and prisma-postgres skills whenever you're working with Prisma
- Use the nodejs-backend-patterns skill whenever you're working on the node.js Fastify api project
- Use the improve-codebase-architecture skill whenever appropriate 

## Code Locations

Here is what we want to store in each of the directories of this "MBOSS" root-level, super-project:
- ./ - The root directory is used for convenience to store every related Git repo as a submodule for development, and to store a docker compose file which will track the latest commit on the latest version branch of each submodule needed to run the cloud stack locally (i.e., mboss-nodejs-api, mboss-nodejs-dbos, mboss-web) and additional servers (i.e., postgres, weaviate, docling)
- ./design-docs/ - Used to store transient design documents that will be produced by this prompt. Create this directory if it doesn't exist.
- ./mboss-database/ - Used to store Prisma database migrations and shared data models. Will be added as a Git submodule to mboss-nodejs-api and other projects as needed.
- ./mboss-nodejs-api/ - A Node.js API built with TypeScript, Fastify and the shared data models from ./mboss-database/ and serves as the only interface to the mBoss Postgres database (note: we need to ensure that this API has one or more endpoints that can accept a flag to indicate that we want to use DBOS's idempotency superpower where the application and workflow share the same Postgres database as documented here: https://www.dbos.dev/blog/co-locating-workflow-state-with-your-data)
- ./mboss-nodejs-dbos/ - A Node.js Worker built with TypeScript, DBOS, the shared Zod models from ./mboss-zod/, and the shared data models from ./mboss-database/ (needs to support passing in a transaction flag to the API when we want to perform an idempotent operations that require the DBOS workflow and application's data to live in the same Postgres database)
- ./mboss-vscode/ - The mBoss VS Code Extension that will be built with TypeScript and React Flow. 
- ./mboss-web/ - The mBoss Next.js UI that will be built with TypeScript and the shared data models from ./mboss-database/
- ./mboss-zod/ - The mBoss Zod schemas that are used and shared as needed across the other projects. Will be added as a Git submodule to other projects as needed.
- ./prompts/ - Temporary area for the user to edit ad-hoc prompts.
- ./scratch/ - Temporary area for the subagents to store notes/scratch data to pass between steps.


## Design Docs, Mockup, Current Code & Implementation Plan

### Review the User's request and mockups

#### (Step 1) - Review the user's request and any mockups
Launch a new sonnet-engineer subagent to:
- Download any Claude Design files specified by the user. 
- Review the user's request and identify relevant aspects of the Claude Design files
- Conduct any web searches necessary to research the user's request. 
- Then document findings for a subsequent subagent in the ./scratch/ directory.

### Review the Design Docs & Plan 

#### (Step 2) - Review the design docs
Launch a separate, new sonnet-engineer subagent to explore and summarize the contents of each of the following design documents--specifically from the perspective of needing to implement the task(s) the user requested--for a subsequent subagent within the ./scratch/ directory:
- current system's most recent design document: ./design-docs/current-design.md 
- overall set of design changes we need to implement, which may be partially done: ./design-docs/design-delta.md
- overall implementation plan we need to implement, which may be partially done: ./design-docs/plan.md
- vision brief: ./design-docs/mboss-vision-brief.md


### Review the codebase

#### (Step 3) - Review the current state of the codebase 
Launch a new sonnet-engineer subagent to review the code in each of the following directories from the perspectives of how it differs from the current-design.md, design-delta.md and plan.md; and the task(s) the user requested to have implemented. Record notes within the ./scratch/ directory for subsequent subagents:
- ./
- ./mboss-database/
- ./mboss-nodejs-api/
- ./mboss-nodejs-dbos/
- ./mboss-vscode/
- ./mboss-web/
- ./mboss-zod/


### Cross-Project, TDD Implemenation

#### (Step 4) - Design the TDD Plan 
Launch a new opus-engineer subagent to:
- Review the output of the (Step 1), (Step 2) and (Step 3) subagents
- Assemble an overall test-driven development plan using Playwright and Unit tests as appropriate for the specific task(s) that the user requested to have completed (note: we have a Playwright plugin and MCP server)
- Be sure to note any cross-repo dependencies across the different Git Submodules within this root project (i.e., since we won't want to run the /release-* commands until the very end of this set of steps, sometimes we'll need to commit code to a repo, and then update submodule pointers to that repo in order to write the next piece of code or to get a test to pass)
- Document this design in the TDD ./scratch/ directory for a subsequent subagent 


#### (Step 5) - Implement the TDD Plan
Important: Stop and ask the user to review and approve the TDD Plan from (Step 4).

Launch a new opus-engineer subagent to:
- Review the output of the (Step 1), (Step 2), (Step 3) and (Step 4) subagents.
- Use test-driven development with unit tests and Playwright end-to-end tests, as appropriate, to implement the TDD Plan assembled by the (Step 4) subagent 
- The Dockerfile in the root repo and its docker compose should be pointed at the nested submodules, which should always have the latest dev code (though sometimes we'll need to bring containers down and back up to get new code running in there)
- Commit the code and update submodule pointers, only as needed to get the code to pass tests


#### (Step 6) - Commit the implementation
Launch a new sonnet-engineer subagent to:
- Review, commit and push any outstanding code changes from (Step 5) that are still uncommitted

### Review and Revise the Cross-Project, TDD Implemenation

#### (Step 7) - Review the implementation
Launch a new opus-engineer subagent to:
- Review the output of the (Step 1), (Step 2), (Step 3), (Step 4) and (Step 5) subagents.
- Assemble a list of recommended revisions to the TDD implementation from (Step 5) within the ./scratch/ directory for a subsequent subagent.


#### (Step 8) - Review the Recommended Revisions
Launch a new sonnet-engineer subagent to:
- Review the output of the (Step 1), (Step 2), (Step 3), (Step 4), (Step 5) and (Step 7) subagents.
- Then determine which of the recommended revisions from (Step 7) are actually valid.


#### (Step 9) - Review the Recommended Revisions
Launch a new sonnet-engineer subagent to:
- Review the output of the (Step 1), (Step 2), (Step 3), (Step 4), (Step 5) and (Step 7) subagents.
- Then determine which of the recommended revisions from (Step 7) are actually necessary.


#### (Step 10) - Identify Revisions to Implement
Launch a new sonnet-engineer subagent to:
- Review the output of the (Step 8) and (Step 9) subagents. 
- Then determine if any of the recommended revisions from (Step 7) are both valid and necessary.
- If no revisions are necessary, then skip ahead to (Step 12)
- If there are revisions which are necessary, then instead proceed to (Step 11)


#### (Step 11) - Implement Revisions to tests and code
Launch a new opus-engineer subagent to:
- Review the output of the (Step 1), (Step 2), (Step 3), (Step 4), (Step 5) and (Step 10) subagents.
- Use test-driven development with unit tests and Playwright end-to-end tests, as appropriate, to implement the recommended revisions to the code and tests deemed both valid and necessary by the (Step 10) subagent.
- The Dockerfile in the root repo and its docker compose should be pointed at the nested submodules, which should always have the latest dev code (though sometimes we'll need to bring containers down and back up to get new code running in there)
- Commit the code and update submodule pointers, only as needed to get the code to pass tests


#### (Step 12) - Commit the revisions
Launch a new sonnet-engineer subagent to:
- Review, commit and push any outstanding code changes from (Step 11) that are still uncommitted


### Release 

#### (Step 13) - Release all changes in GitHub
Launch a new sonnet-engineer subagent to:
- Release any updated projects that are submodules via the /release-* commands
- Finally, release the root project with /release-root

### Update the Implemenation Plan

#### (Step 14) - Update the Plan's Task List
- If, and only if, applicable: Mark each completed task from the implementation plan in ./design-docs/plan.md Done with a Green Checkmark Emoji next to its number in the table

