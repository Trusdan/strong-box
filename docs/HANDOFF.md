# Handing a task to an AI coding agent

How the maintainer hands one task at a time to an AI coding agent (such as Claude Code) and reviews the result. The agent's own rules are in [`CLAUDE.md`](../CLAUDE.md).

## The loop

1. **Pick the next task.** In the issue tracker, filter for open tasks labelled for the agent, in rank order. Take the first one whose "is blocked by" links are all done.
2. **Start the agent** in a fresh clone, or a clean, up-to-date `main` (`git checkout main && git pull`).
3. **Give it the whole task** (title and description) and add: "Follow CLAUDE.md. Work on a new branch `claude/<KEY>-<slug>`. When done, run tools/run_tests.sh and open a PR into main using the PR template. Do not merge."
4. **Let it work.** If it asks a question, answer it. Anything that changes the scope goes into the task as a comment, so the next session sees it too.
5. **Review the pull request.**
   - Read the description first.
   - Then read the tests: they are the contract.
   - Then read the code.
   - Check that CI is green on both `test` (Ubuntu) and `test-windows` (Windows), that only files in the task's "May touch" list changed, and that no host-game names appear anywhere.
6. **Request changes** with pull request review comments. Then ask the agent to "address the review comments on PR #N".
7. **Merge it yourself** with a squash merge, mark the task done, and pick the next one.

## Stop and ask

Stop the agent and ask what is going on if:

- it wants to edit vendored folders (`addons/gut/`), CI workflows or secrets when the task did not ask for that; or
- the pull request grows far past about 600 changed lines.
