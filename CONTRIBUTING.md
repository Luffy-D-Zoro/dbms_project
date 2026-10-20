# Contributing Guide

This is a six-member college DBMS project. We use GitHub Issues to plan work and Pull Requests (PRs) to review changes before merging them into `main`.

## 1. Basic rules

- **No issue, no implementation.** Create or link an issue before starting a task.
- **One owner per issue.** An issue can have only one assignee at a time. Others can discuss or review it, but should not independently implement it.
- **One active issue per member.** Finish, hand off, or unassign your current issue before claiming another. Reviewing other people's PRs is always allowed.
- **Stay inside the issue's scope.** Only implement what the issue describes. No unrelated refactoring, extra features, or database changes in the same PR.
- **No direct pushes to `main`.** Work in a separate branch and open a PR.
- **No self-merging.** At least one other member must approve the PR; a designated maintainer merges it.
- Be respectful in reviews. Comment on the code and reasoning, not the person.

## 2. Creating and claiming issues

Anyone can suggest an issue. Before it is picked up, the issue should explain:

- **Goal:** What problem are we solving?
- **In scope:** Exactly what needs to be changed.
- **Out of scope:** Related work that is *not* part of this issue.
- **Acceptance criteria:** How we will decide the task is done.
- **Dependencies:** Other issues, schema decisions, or APIs needed first (if any).

If an issue is unclear, discuss it before starting. Do not guess the requirements.

To claim an issue:

1. Check that it is unassigned, ready to start, and not blocked by another task.
2. Make sure you have no other active issue.
3. Assign yourself and comment that you are taking it. If self-assignment is unavailable, comment and ask a maintainer to assign you.
4. If you cannot continue, explain the blocker and ask to hand off/unassign the issue. Do not leave it silently claimed.

## 3. Scope changes

**The issue defines the scope of the PR.** If you discover another bug or a useful improvement while working:

1. Describe it in the issue or team discussion.
2. Create a separate issue for unrelated work.
3. If the change is necessary to finish the current issue, agree on it with a maintainer/reviewer and update the issue description *before* implementing it.

A PR containing unapproved out-of-scope changes will be asked to split or remove them.

## 4. Branches and commits

Start from an up-to-date `main` and create **one branch per issue**:

```bash
git switch main
git pull origin main
git switch -c issue/12-user-schema
```

Use a branch name like `issue/<number>-<short-description>`. Do not work directly on `main` or reuse a branch for a different issue.

Make small, meaningful commits, for example:

- `feat(db): add organization table`
- `fix(api): validate membership input`
- `docs: update ER diagram`

Do not commit `.env` files, passwords, tokens, personal data, build output, or temporary files.

## 5. Database and integration rules

Because the modules share one database, schema changes affect other members.

- Agree on shared entity names, primary keys, foreign keys, and relationships before implementing dependent modules.
- Put SQL schema changes in versioned migration files once we decide the database stack; do not silently edit a shared database by hand.
- Update the ER diagram/schema documentation when a change affects tables or relationships.
- Call out migrations, changed APIs, and any breaking changes in the PR description.
- Do not rename/drop shared columns or tables without discussing the effect on other modules first.
- Include sample data or reproduction steps when needed to test a change.

## 6. Pull requests

Open a PR from your issue branch into `main`. Prefer a **draft PR** if the work is not yet ready for review.

The PR should:

- Link the issue with `Closes #12` (replace `12` with the real issue number).
- Explain **what changed**, **why**, and **how it was tested**.
- Mention database migrations, dependency changes, UI screenshots, or breaking changes if relevant.
- Be limited to the claimed issue; split unrelated work into separate issues/PRs.
- Have no unresolved review comments before merging.

If tests are not available yet, clearly state what you checked manually. Do not mark an untested change as tested.

## 7. Review and merge

- At least **one reviewer other than the PR author** must approve the PR.
- Reviewers should check correctness, issue scope, database compatibility, and the tests/reproduction steps.
- The author responds to feedback and updates the **same PR**.
- After approval, a designated maintainer **squash-merges** the PR into `main` and deletes the feature branch.
- The linked issue should close after merging. Confirm this on GitHub.

If a review is stuck or people disagree, discuss the specific trade-off on the PR or issue and ask a maintainer to make a final call.

## 8. Quick checklist before requesting review

- [ ] My issue was assigned to me and my work stays within its scope.
- [ ] I used a separate issue branch (not `main`).
- [ ] I verified the change and documented how I tested it.
- [ ] I updated any affected database/schema documentation.
- [ ] I did not commit secrets, generated files, or unrelated changes.
- [ ] My PR links the issue and explains any relevant impact.

For questions or new ideas, start with an issue rather than changing an unrelated PR.
