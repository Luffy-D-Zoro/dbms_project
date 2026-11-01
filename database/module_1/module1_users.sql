-- =====================================================================
-- MODULE 1: User, Authentication & Access Management
-- Open Source Organization Collaboration & Contribution Management System
-- Database: MySQL / MariaDB (XAMPP), InnoDB
-- Tables: users, profiles, roles, permissions, user_roles, role_permissions
-- =====================================================================

CREATE DATABASE IF NOT EXISTS oss_collab CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE oss_collab;

-- ---------- Entity: Role ----------
CREATE TABLE IF NOT EXISTS roles (
    role_id     INT AUTO_INCREMENT PRIMARY KEY,
    name        VARCHAR(50)  NOT NULL UNIQUE,
    description VARCHAR(255)
);

-- ---------- Entity: Permission ----------
CREATE TABLE IF NOT EXISTS permissions (
    permission_id INT AUTO_INCREMENT PRIMARY KEY,
    code          VARCHAR(60) NOT NULL UNIQUE,      -- e.g. PR_MERGE
    description   VARCHAR(255)
);

-- ---------- Junction: Role <-> Permission (M:N) ----------
CREATE TABLE IF NOT EXISTS role_permissions (
    role_id       INT NOT NULL,
    permission_id INT NOT NULL,
    PRIMARY KEY (role_id, permission_id),
    FOREIGN KEY (role_id)       REFERENCES roles(role_id)             ON DELETE CASCADE,
    FOREIGN KEY (permission_id) REFERENCES permissions(permission_id) ON DELETE CASCADE
);

-- ---------- Entity: User ----------
CREATE TABLE IF NOT EXISTS users (
    user_id       INT AUTO_INCREMENT PRIMARY KEY,
    username      VARCHAR(50)  NOT NULL UNIQUE,
    email         VARCHAR(120) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,            -- never store a plain password
    status        ENUM('ACTIVE','SUSPENDED','DELETED') NOT NULL DEFAULT 'ACTIVE',
    created_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_login    DATETIME NULL
);

-- ---------- Entity: Profile (1:1 with User) ----------
CREATE TABLE IF NOT EXISTS profiles (
    profile_id INT AUTO_INCREMENT PRIMARY KEY,
    user_id    INT NOT NULL UNIQUE,                 -- UNIQUE makes it one-to-one
    full_name  VARCHAR(100) NOT NULL,
    bio        TEXT,
    avatar_url VARCHAR(255),
    location   VARCHAR(100),
    website    VARCHAR(255),
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE
);

-- ---------- Junction: User <-> Role (M:N) ----------
CREATE TABLE IF NOT EXISTS user_roles (
    user_id INT NOT NULL,
    role_id INT NOT NULL,
    PRIMARY KEY (user_id, role_id),
    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
    FOREIGN KEY (role_id) REFERENCES roles(role_id) ON DELETE CASCADE
);

-- =====================================================================
-- SAMPLE DATA
-- (password_hash values are placeholders. Create real logins through the
--  register page so PHP's password_hash() generates the hash.)
-- =====================================================================
INSERT INTO roles (name, description) VALUES
 ('Admin','Full control'),
 ('Maintainer','Manage repos and merge PRs'),
 ('Contributor','Submit issues and PRs');

INSERT INTO permissions (code, description) VALUES
 ('ORG_MANAGE','Manage organization settings'),
 ('REPO_WRITE','Push and create branches'),
 ('PR_MERGE','Merge pull requests'),
 ('ISSUE_CREATE','Create issues'),
 ('REVIEW_SUBMIT','Submit reviews');

INSERT INTO role_permissions (role_id, permission_id) VALUES
 (1,1),(1,2),(1,3),(1,4),(1,5),      -- Admin: everything
 (2,2),(2,3),(2,4),(2,5),            -- Maintainer
 (3,4),(3,5);                        -- Contributor

INSERT INTO users (username, email, password_hash) VALUES
 ('aarav','aarav@example.com','placeholder_hash_1'),
 ('priya','priya@example.com','placeholder_hash_2'),
 ('rohan','rohan@example.com','placeholder_hash_3'),
 ('meera','meera@example.com','placeholder_hash_4'),
 ('kabir','kabir@example.com','placeholder_hash_5');   -- no profile on purpose (for Q4)

INSERT INTO profiles (user_id, full_name, bio, location) VALUES
 (1,'Aarav Sharma','Backend dev and OSS maintainer','Jabalpur'),
 (2,'Priya Verma','Frontend engineer','Bhopal'),
 (3,'Rohan Patel','Docs and testing contributor','Pune'),
 (4,'Meera Iyer','DevOps enthusiast','Chennai');

INSERT INTO user_roles (user_id, role_id) VALUES
 (1,1),(1,2),   -- Aarav: Admin + Maintainer (shows many-to-many)
 (2,2),         -- Priya: Maintainer
 (3,3),         -- Rohan: Contributor
 (4,3);         -- Meera: Contributor

-- =====================================================================
-- VIEW: every permission each user has (through their roles)
-- =====================================================================
CREATE OR REPLACE VIEW user_permissions AS
SELECT DISTINCT u.user_id, u.username, p.code AS permission
FROM users u
JOIN user_roles       ur ON ur.user_id       = u.user_id
JOIN role_permissions rp ON rp.role_id       = ur.role_id
JOIN permissions      p  ON p.permission_id  = rp.permission_id;

-- =====================================================================
-- TRIGGER: every new user automatically becomes a Contributor
-- (created after the sample data so the sample roles stay as written)
-- =====================================================================
DELIMITER //
CREATE TRIGGER trg_user_default_role
AFTER INSERT ON users
FOR EACH ROW
BEGIN
    INSERT INTO user_roles (user_id, role_id)
    SELECT NEW.user_id, role_id FROM roles WHERE name = 'Contributor';
END//
DELIMITER ;

-- Try it:  INSERT INTO users (username,email,password_hash) VALUES ('neha','neha@example.com','x');
--          SELECT * FROM user_roles WHERE user_id = LAST_INSERT_ID();   -- shows Contributor

-- =====================================================================
-- DEMO QUERIES  (expected output is in the PDF guide)
-- =====================================================================
-- Q1  Users with their profile
SELECT u.username, u.email, p.full_name, p.location
FROM users u JOIN profiles p ON p.user_id = u.user_id
ORDER BY u.user_id;

-- Q2  Roles of one user
SELECT u.username, r.name AS role
FROM users u
JOIN user_roles ur ON ur.user_id = u.user_id
JOIN roles r       ON r.role_id  = ur.role_id
WHERE u.username = 'aarav';

-- Q3  Permissions of one user (3-table join through the junction tables)
SELECT DISTINCT p.code
FROM users u
JOIN user_roles ur       ON ur.user_id      = u.user_id
JOIN role_permissions rp ON rp.role_id      = ur.role_id
JOIN permissions p       ON p.permission_id = rp.permission_id
WHERE u.username = 'priya';

-- Q4  Users who have no profile yet
SELECT u.user_id, u.username
FROM users u LEFT JOIN profiles p ON p.user_id = u.user_id
WHERE p.profile_id IS NULL;

-- Q5  Number of users in each role
SELECT r.name AS role, COUNT(ur.user_id) AS total_users
FROM roles r LEFT JOIN user_roles ur ON ur.role_id = r.role_id
GROUP BY r.role_id, r.name;

-- Q6  Number of permissions in each role
SELECT r.name AS role, COUNT(rp.permission_id) AS total_permissions
FROM roles r LEFT JOIN role_permissions rp ON rp.role_id = r.role_id
GROUP BY r.role_id, r.name;

-- Q7  Permission check: may Rohan merge pull requests? (0 = no, 1 = yes)
SELECT COUNT(*) AS allowed
FROM user_permissions WHERE username = 'rohan' AND permission = 'PR_MERGE';

-- Q8  All permissions of Aarav using the view
SELECT permission FROM user_permissions WHERE username = 'aarav' ORDER BY permission;
