-- ============================================================
-- Sample data for Module 4
-- ============================================================

-- Parent data (stubs)
INSERT INTO users (user_id, username) VALUES
(1, 'alice'),
(2, 'bob'),
(3, 'charlie');

INSERT INTO repositories (repo_id, name) VALUES
(10, 'compiler'),
(11, 'debugger');

INSERT INTO branches (branch_id, repo_id, name) VALUES
(100, 10, 'main'),
(101, 10, 'feature/login'),
(102, 11, 'main');

INSERT INTO issues (issue_id, repo_id, title) VALUES
(25, 10, 'Fix login validation'),
(26, 10, 'Add unit tests for auth'),
(30, 11, 'Crash on null pointer');

-- Module 4 data
INSERT INTO assignments (issue_id, user_id, assigned_by, status, due_date) VALUES
(25, 1, 3, 'in_progress', '2026-11-20'),   -- Alice assigned to issue 25 by Charlie
(25, 2, 3, 'open',        '2026-11-22'),   -- Bob also assigned to same issue
(26, 1, 3, 'open',        '2026-11-25');

INSERT INTO pull_requests
    (repo_id, author_id, source_branch_id, target_branch_id, title, description, status)
VALUES
(10, 1, 101, 100, 'Add login validation', 'Implements the fix for issue 25', 'open'),
(10, 2, 101, 100, 'Extra tests',          'Adds more coverage',             'open');

-- Assume the first PR got pr_id = 1, second = 2 (AUTO_INCREMENT)
INSERT INTO pr_issue_relations (pr_id, issue_id, relation_type) VALUES
(1, 25, 'fixes'),
(1, 26, 'related'),
(2, 26, 'fixes');

INSERT INTO contributions (user_id, repo_id, pr_id, type, description, points) VALUES
(1, 10, 1, 'code',  'Implemented login validation logic', 10),
(2, 10, 2, 'code',  'Added unit tests',                   5),
(1, 10, NULL, 'docs', 'Updated README for auth module',    2);


-- ============================================================
-- Verification queries
-- ============================================================

-- 1. All assignments with assignee and assigner names
SELECT 
    a.assignment_id,
    i.title          AS issue,
    u1.username      AS assignee,
    u2.username      AS assigned_by,
    a.status,
    a.due_date
FROM assignments a
JOIN issues i     ON a.issue_id    = i.issue_id
JOIN users  u1    ON a.user_id     = u1.user_id
JOIN users  u2    ON a.assigned_by = u2.user_id
ORDER BY a.assignment_id;

-- 2. Pull requests with author and branch names
SELECT 
    pr.pr_id,
    pr.title,
    u.username           AS author,
    r.name               AS repository,
    sb.name              AS source_branch,
    tb.name              AS target_branch,
    pr.status
FROM pull_requests pr
JOIN users        u  ON pr.author_id        = u.user_id
JOIN repositories r  ON pr.repo_id          = r.repo_id
JOIN branches     sb ON pr.source_branch_id = sb.branch_id
JOIN branches     tb ON pr.target_branch_id = tb.branch_id
ORDER BY pr.pr_id;

-- 3. Which issues does each PR address?
SELECT 
    pr.pr_id,
    pr.title          AS pr_title,
    i.issue_id,
    i.title           AS issue_title,
    rel.relation_type
FROM pr_issue_relations rel
JOIN pull_requests pr ON rel.pr_id   = pr.pr_id
JOIN issues        i  ON rel.issue_id = i.issue_id
ORDER BY pr.pr_id, i.issue_id;

-- 4. Contributions with points
SELECT 
    c.contribution_id,
    u.username,
    r.name            AS repository,
    c.pr_id,
    c.type,
    c.points,
    c.description
FROM contributions c
JOIN users        u ON c.user_id = u.user_id
JOIN repositories r ON c.repo_id = r.repo_id
ORDER BY c.contribution_id;