-- ============================================================
-- Module 4: Task Assignment & Contribution
-- ============================================================
-- NOTE:
-- This script includes minimal stub tables for users, issues,
-- repositories and branches so Module 4 can be tested even if
-- Modules 1-3/5 are not ready yet.
-- Once the real tables exist, remove the stub CREATE TABLE
-- statements and keep only the Module 4 tables + sample data.
-- ============================================================

-- ------------------------------------------------------------
-- 0. Minimal parent stubs (REMOVE when real modules exist)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS users (
    user_id      INT PRIMARY KEY,
    username     VARCHAR(50) NOT NULL
);

CREATE TABLE IF NOT EXISTS repositories (
    repo_id      INT PRIMARY KEY,
    name         VARCHAR(100) NOT NULL
);

CREATE TABLE IF NOT EXISTS branches (
    branch_id    INT PRIMARY KEY,
    repo_id      INT NOT NULL,
    name         VARCHAR(100) NOT NULL,
    FOREIGN KEY (repo_id) REFERENCES repositories(repo_id)
);

CREATE TABLE IF NOT EXISTS issues (
    issue_id     INT PRIMARY KEY,
    repo_id      INT NOT NULL,
    title        VARCHAR(200) NOT NULL,
    FOREIGN KEY (repo_id) REFERENCES repositories(repo_id)
);

-- ------------------------------------------------------------
-- 1. Module 4 tables
-- ------------------------------------------------------------

-- assignments
CREATE TABLE IF NOT EXISTS assignments (
    assignment_id   INT PRIMARY KEY AUTO_INCREMENT,
    issue_id        INT NOT NULL,
    user_id         INT NOT NULL,          -- assignee
    assigned_by     INT NOT NULL,          -- who assigned
    status          VARCHAR(30) NOT NULL DEFAULT 'open',
    assigned_at     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    due_date        DATE NULL,
    FOREIGN KEY (issue_id)    REFERENCES issues(issue_id),
    FOREIGN KEY (user_id)     REFERENCES users(user_id),
    FOREIGN KEY (assigned_by) REFERENCES users(user_id)
);

-- pull_requests
CREATE TABLE IF NOT EXISTS pull_requests (
    pr_id               INT PRIMARY KEY AUTO_INCREMENT,
    repo_id             INT NOT NULL,
    author_id           INT NOT NULL,
    source_branch_id    INT NOT NULL,
    target_branch_id    INT NOT NULL,
    title               VARCHAR(200) NOT NULL,
    description         TEXT,
    status              VARCHAR(30) NOT NULL DEFAULT 'open',
    created_at          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    merged_at           DATETIME NULL,
    FOREIGN KEY (repo_id)          REFERENCES repositories(repo_id),
    FOREIGN KEY (author_id)        REFERENCES users(user_id),
    FOREIGN KEY (source_branch_id) REFERENCES branches(branch_id),
    FOREIGN KEY (target_branch_id) REFERENCES branches(branch_id)
);

-- pr_issue_relations (many-to-many)
CREATE TABLE IF NOT EXISTS pr_issue_relations (
    pr_id           INT NOT NULL,
    issue_id        INT NOT NULL,
    relation_type   VARCHAR(30) NOT NULL DEFAULT 'related',  -- e.g. fixes, closes, related
    PRIMARY KEY (pr_id, issue_id),
    FOREIGN KEY (pr_id)    REFERENCES pull_requests(pr_id),
    FOREIGN KEY (issue_id) REFERENCES issues(issue_id)
);

-- contributions
CREATE TABLE IF NOT EXISTS contributions (
    contribution_id INT PRIMARY KEY AUTO_INCREMENT,
    user_id         INT NOT NULL,
    repo_id         INT NOT NULL,
    pr_id           INT NULL,                 -- optional
    type            VARCHAR(50) NOT NULL,     -- e.g. code, docs, triage
    description     TEXT,
    points          INT DEFAULT 0,
    contributed_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(user_id),
    FOREIGN KEY (repo_id) REFERENCES repositories(repo_id),
    FOREIGN KEY (pr_id)   REFERENCES pull_requests(pr_id)
);
-- git fetch origin
-- git checkout 6-task-module-4-task-assignment-contribution
-- 