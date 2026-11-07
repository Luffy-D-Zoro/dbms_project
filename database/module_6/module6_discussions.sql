-- =====================================================================
-- Module 6: Discussion, Notification & Activity
-- Project : Open Source Organization Collaboration & Contribution
--           Management System
-- DB      : MySQL 8.0.16+ / MariaDB 10.2.2+ (XAMPP), InnoDB, utf8mb4
-- Tables  : discussions, comments, subscriptions, notifications,
--           activity_logs
--
-- RUN ORDER: Module 1 file (module1_users.sql) FIRST, then this file.
-- FKs to repositories (M3), issues (M3), pull_requests (M4) are added
-- later (Section 7) once those modules are merged.
--
-- FIXED VERSION (tested on MariaDB 10.11 with Module 1's users table):
--   FIX 1: removed "DEFAULT CHARSET=utf8mb4" from every table, so tables use the
--          database collation (utf8mb4_unicode_ci) like Module 1. Before, every
--          comment INSERT failed with ERROR 1267 (illegal mix of collations).
--   FIX 2: BEFORE INSERT trigger now lets the FK report a missing parent comment
--          (before it gave a misleading "same thread" error).
--   FIX 3: new BEFORE UPDATE trigger on comments: parent and thread cannot be
--          changed after insert (blocks cycles, thread breaking, lock bypass).
-- =====================================================================

USE oss_collab;

-- Re-run safe: drop Module 6 objects (child tables first)
-- WARNING: this deletes all Module 6 data. Do not run it on a database with real data.
DROP VIEW  IF EXISTS v_unread_notifications;
DROP VIEW  IF EXISTS v_discussion_comment_counts;
DROP TABLE IF EXISTS notifications;
DROP TABLE IF EXISTS subscriptions;
DROP TABLE IF EXISTS activity_logs;
DROP TABLE IF EXISTS comments;
DROP TABLE IF EXISTS discussions;

-- =====================================================================
-- SECTION 1: TABLES
-- =====================================================================

-- 1) discussions : a conversation thread inside a repository
CREATE TABLE discussions (
    discussion_id INT AUTO_INCREMENT PRIMARY KEY,
    repo_id       INT          NOT NULL,          -- FK -> repositories (M3), added in Section 7
    author_id     INT          NOT NULL,          -- FK -> users (M1)
    title         VARCHAR(200) NOT NULL,
    body          TEXT,
    category      ENUM('general','q_and_a','ideas','announcement') NOT NULL DEFAULT 'general',
    is_locked     TINYINT(1)   NOT NULL DEFAULT 0, -- 1 = no new comments allowed
    created_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_discussions_author
        FOREIGN KEY (author_id) REFERENCES users(user_id),

    INDEX idx_discussions_repo (repo_id)
) ENGINE=InnoDB;                                  -- FIX 1: no DEFAULT CHARSET here

-- 2) comments : a comment on a discussion OR an issue OR a pull request
--    (exactly one of the three), optionally replying to another comment
CREATE TABLE comments (
    comment_id        INT AUTO_INCREMENT PRIMARY KEY,
    author_id         INT      NOT NULL,           -- FK -> users (M1)
    discussion_id     INT      NULL,               -- FK -> discussions (M6)
    issue_id          INT      NULL,               -- FK -> issues (M3), added in Section 7
    pr_id             INT      NULL,               -- FK -> pull_requests (M4), added in Section 7
    parent_comment_id INT      NULL,               -- FK -> comments (self-reference, for replies)
    body              TEXT     NOT NULL,
    created_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- Rule 1 from the team guide: exactly ONE parent must be set
    CONSTRAINT chk_comments_one_parent CHECK (
        (discussion_id IS NOT NULL) + (issue_id IS NOT NULL) + (pr_id IS NOT NULL) = 1
    ),

    CONSTRAINT fk_comments_author
        FOREIGN KEY (author_id) REFERENCES users(user_id),
    -- No ON DELETE action here on purpose: MySQL does not allow a column used in a
    -- CHECK constraint to also have CASCADE / SET NULL on its foreign key.
    -- (So a discussion that still has comments cannot be deleted: delete its comments first.)
    CONSTRAINT fk_comments_discussion
        FOREIGN KEY (discussion_id) REFERENCES discussions(discussion_id),
    CONSTRAINT fk_comments_parent
        FOREIGN KEY (parent_comment_id) REFERENCES comments(comment_id)
        ON DELETE CASCADE,                          -- delete a comment -> its replies go too

    INDEX idx_comments_issue (issue_id),
    INDEX idx_comments_pr (pr_id)
) ENGINE=InnoDB;                                  -- FIX 1

-- 3) subscriptions : who follows what (polymorphic target, no FK on target)
CREATE TABLE subscriptions (
    subscription_id INT AUTO_INCREMENT PRIMARY KEY,
    user_id         INT      NOT NULL,             -- FK -> users (M1)
    target_type     ENUM('repository','discussion','issue','pull_request') NOT NULL,
    target_id       INT      NOT NULL,             -- polymorphic: app validates it
    created_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_subscriptions_user
        FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
    -- Design suggestion (not in team guide): a user cannot follow the same thing twice
    CONSTRAINT uq_subscription UNIQUE (user_id, target_type, target_id),

    INDEX idx_subscriptions_target (target_type, target_id)
) ENGINE=InnoDB;                                  -- FIX 1

-- 4) notifications : an alert delivered to one user
CREATE TABLE notifications (
    notification_id INT AUTO_INCREMENT PRIMARY KEY,
    user_id         INT          NOT NULL,         -- FK -> users (M1), the receiver
    type            VARCHAR(50)  NOT NULL,         -- e.g. new_comment, mention, pr_review
    message         VARCHAR(255) NOT NULL,
    target_type     ENUM('repository','discussion','issue','pull_request','comment') NULL,
    target_id       INT          NULL,             -- polymorphic: app validates it
    is_read         TINYINT(1)   NOT NULL DEFAULT 0,
    created_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_notifications_user
        FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,

    INDEX idx_notifications_user_read (user_id, is_read)
) ENGINE=InnoDB;                                  -- FIX 1

-- 5) activity_logs : audit record of who did what (append-only)
CREATE TABLE activity_logs (
    log_id      INT AUTO_INCREMENT PRIMARY KEY,
    user_id     INT          NULL,                 -- FK -> users (M1); NULL = system action
    action      VARCHAR(50)  NOT NULL,             -- e.g. login, comment_created
    entity_type VARCHAR(30)  NULL,                 -- polymorphic: comment, issue, repo ...
    entity_id   INT          NULL,
    details     VARCHAR(255) NULL,
    ip_address  VARCHAR(45)  NULL,                 -- 45 chars fits IPv6
    created_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_activity_user
        FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE SET NULL, -- history survives

    INDEX idx_activity_entity (entity_type, entity_id),
    INDEX idx_activity_user (user_id, created_at)
) ENGINE=InnoDB;                                  -- FIX 1

-- =====================================================================
-- SECTION 2: TRIGGERS
-- =====================================================================
DROP TRIGGER IF EXISTS trg_comments_before_insert;
DROP TRIGGER IF EXISTS trg_comments_after_insert;
DROP TRIGGER IF EXISTS trg_comments_before_update;

DELIMITER $$

-- Before a comment is saved:
--  (a) block comments on a locked discussion
--  (b) Rule 2: a reply must stay in the same thread as its parent
--      (cycles cannot happen on INSERT, because the parent must already exist)
CREATE TRIGGER trg_comments_before_insert
BEFORE INSERT ON comments
FOR EACH ROW
BEGIN
    DECLARE v_locked TINYINT DEFAULT 0;
    DECLARE v_p_disc INT;
    DECLARE v_p_issue INT;
    DECLARE v_p_pr INT;

    IF NEW.discussion_id IS NOT NULL THEN
        SELECT is_locked INTO v_locked
        FROM discussions WHERE discussion_id = NEW.discussion_id;
        IF v_locked = 1 THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'This discussion is locked. New comments are not allowed.';
        END IF;
    END IF;

    -- FIX 2: if the parent does not exist, skip the check; the FK raises the proper error
    IF NEW.parent_comment_id IS NOT NULL
       AND EXISTS (SELECT 1 FROM comments WHERE comment_id = NEW.parent_comment_id) THEN
        SELECT discussion_id, issue_id, pr_id
          INTO v_p_disc, v_p_issue, v_p_pr
        FROM comments WHERE comment_id = NEW.parent_comment_id;

        -- <=> is NULL-safe equals (NULL <=> NULL is TRUE)
        IF NOT (v_p_disc <=> NEW.discussion_id
                AND v_p_issue <=> NEW.issue_id
                AND v_p_pr <=> NEW.pr_id) THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'A reply must be in the same thread as its parent comment.';
        END IF;
    END IF;
END$$

-- After a comment is saved:
--  (a) notify every subscriber of that discussion/issue/PR (except the commenter)
--  (b) write an activity log row
CREATE TRIGGER trg_comments_after_insert
AFTER INSERT ON comments
FOR EACH ROW
BEGIN
    DECLARE v_type VARCHAR(20);
    DECLARE v_id INT;

    IF NEW.discussion_id IS NOT NULL THEN
        SET v_type = 'discussion',   v_id = NEW.discussion_id;
    ELSEIF NEW.issue_id IS NOT NULL THEN
        SET v_type = 'issue',        v_id = NEW.issue_id;
    ELSE
        SET v_type = 'pull_request', v_id = NEW.pr_id;
    END IF;

    INSERT INTO notifications (user_id, type, message, target_type, target_id)
    SELECT s.user_id,
           'new_comment',
           CONCAT('New comment on ', v_type, ' #', v_id),
           v_type,
           v_id
    FROM subscriptions s
    WHERE s.target_type = v_type
      AND s.target_id   = v_id
      AND s.user_id    <> NEW.author_id;

    INSERT INTO activity_logs (user_id, action, entity_type, entity_id, details)
    VALUES (NEW.author_id, 'comment_created', 'comment', NEW.comment_id,
            CONCAT('Commented on ', v_type, ' #', v_id));
END$$

-- FIX 3: A comment's thread and parent are fixed after insert. This blocks moving a
-- comment into a locked discussion, breaking reply threads, and parent cycles
-- (for example a comment becoming its own parent). Editing the body is still allowed.
CREATE TRIGGER trg_comments_before_update
BEFORE UPDATE ON comments
FOR EACH ROW
BEGIN
    IF NOT (NEW.parent_comment_id <=> OLD.parent_comment_id)
       OR NOT (NEW.discussion_id <=> OLD.discussion_id)
       OR NOT (NEW.issue_id      <=> OLD.issue_id)
       OR NOT (NEW.pr_id         <=> OLD.pr_id) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'A comment cannot be moved to another thread or given a new parent.';
    END IF;
END$$

DELIMITER ;

-- =====================================================================
-- SECTION 3: VIEWS
-- =====================================================================

-- Unread notifications of every user (sort in the query: ORDER BY created_at DESC)
CREATE VIEW v_unread_notifications AS
SELECT notification_id, user_id, type, message, target_type, target_id, created_at
FROM notifications
WHERE is_read = 0;

-- Each discussion with its number of comments
CREATE VIEW v_discussion_comment_counts AS
SELECT d.discussion_id, d.repo_id, d.title, d.is_locked,
       COUNT(c.comment_id) AS comment_count
FROM discussions d
LEFT JOIN comments c ON c.discussion_id = d.discussion_id
GROUP BY d.discussion_id, d.repo_id, d.title, d.is_locked;

-- =====================================================================
-- SECTION 4: SAMPLE DATA
-- Users 1-5 come from Module 1 (aarav, priya, rohan, meera, kabir).
-- repo_id 1-2, issue_id 15 and pr_id 7 are DUMMY values (no FK yet).
-- =====================================================================

-- Subscriptions first, so the trigger creates notifications for later comments
INSERT INTO subscriptions (user_id, target_type, target_id) VALUES
(1, 'issue',        15),   -- aarav follows issue 15
(2, 'discussion',    1),   -- priya follows discussion 1
(4, 'discussion',    1),   -- meera follows discussion 1
(3, 'pull_request',  7),   -- rohan follows PR 7
(1, 'repository',    1);   -- aarav follows repo 1

INSERT INTO discussions (repo_id, author_id, title, body, category, is_locked) VALUES
(1, 1, 'Welcome to the project',  'Introduce yourself here!',       'general',      0),  -- id 1
(1, 2, 'Roadmap for v2',          'What features should v2 have?',  'ideas',        0),  -- id 2
(2, 3, 'v1.0 release thread',     'Release notes for v1.0.',        'announcement', 1);  -- id 3 (locked)

INSERT INTO comments (author_id, discussion_id, issue_id, pr_id, parent_comment_id, body) VALUES
(2, 1,    NULL, NULL, NULL, 'Thanks for setting this up!'),        -- id 1
(1, 1,    NULL, NULL, 1,    'Glad to have you, Priya!'),           -- id 2 (reply to 1)
(3, 1,    NULL, NULL, 2,    'Hello everyone!'),                    -- id 3 (reply to 2)
(2, NULL, 15,   NULL, NULL, 'I can reproduce this bug.'),          -- id 4 (on issue 15)
(4, NULL, NULL, 7,    NULL, 'Looks good, one small fix in line 20.'), -- id 5 (on PR 7)
(5, NULL, 15,   NULL, 4,    'Same problem on Windows.');           -- id 6 (reply to 4)

-- Manual activity rows (one normal, one system action with NULL user)
INSERT INTO activity_logs (user_id, action, entity_type, entity_id, details, ip_address) VALUES
(1,    'login',           NULL,         NULL, 'User logged in',               '192.168.1.10'),
(NULL, 'nightly_cleanup', 'notification', NULL, 'Old read notifications archived', NULL);

-- Mark one notification as read (for demo)
UPDATE notifications SET is_read = 1 WHERE notification_id = 1;

-- =====================================================================
-- SECTION 5: DEMO QUERIES (for presentation / viva)
-- =====================================================================

-- Q1. Unread notifications of user 2 (priya)
SELECT * FROM v_unread_notifications WHERE user_id = 2 ORDER BY created_at DESC;

-- Q2. All comments on issue 15
SELECT comment_id, author_id, parent_comment_id, body, created_at
FROM comments WHERE issue_id = 15 ORDER BY created_at;

-- Q3. Direct replies to comment 1
SELECT comment_id, author_id, body FROM comments WHERE parent_comment_id = 1;

-- Q4. Full reply thread under comment 1 (recursive CTE, any depth)
WITH RECURSIVE thread AS (
    SELECT comment_id, parent_comment_id, body, 0 AS depth
    FROM comments WHERE comment_id = 1
    UNION ALL
    SELECT c.comment_id, c.parent_comment_id, c.body, t.depth + 1
    FROM comments c
    JOIN thread t ON c.parent_comment_id = t.comment_id
)
SELECT * FROM thread ORDER BY depth, comment_id;

-- Q5. Discussions with comment counts
SELECT * FROM v_discussion_comment_counts ORDER BY comment_count DESC;

-- Q6. Who follows discussion 1
SELECT user_id FROM subscriptions WHERE target_type = 'discussion' AND target_id = 1;

-- Q7. Recent activity of user 1
SELECT action, entity_type, entity_id, details, created_at
FROM activity_logs WHERE user_id = 1 ORDER BY created_at DESC LIMIT 10;

-- Q8. Unread notification count per user
SELECT user_id, COUNT(*) AS unread_count
FROM notifications WHERE is_read = 0 GROUP BY user_id;

-- Q9. Most active commenters
SELECT author_id, COUNT(*) AS total_comments
FROM comments GROUP BY author_id ORDER BY total_comments DESC;

-- =====================================================================
-- SECTION 6: CONSTRAINT TESTS (each one SHOULD FAIL)
-- Uncomment one at a time to demo in the viva.
-- =====================================================================

-- T1. Two parents at once -> CHECK chk_comments_one_parent fails
-- INSERT INTO comments (author_id, discussion_id, issue_id, body) VALUES (1, 1, 15, 'bad');

-- T2. No parent at all -> CHECK fails
-- INSERT INTO comments (author_id, body) VALUES (1, 'bad');

-- T3. Comment on locked discussion 3 -> trigger error
-- INSERT INTO comments (author_id, discussion_id, body) VALUES (1, 3, 'bad');

-- T4. Reply in a different thread (parent 4 is on issue 15) -> trigger error
-- INSERT INTO comments (author_id, discussion_id, parent_comment_id, body) VALUES (1, 1, 4, 'bad');

-- T5. Same subscription twice -> UNIQUE uq_subscription fails
-- INSERT INTO subscriptions (user_id, target_type, target_id) VALUES (1, 'issue', 15);

-- T6. Unknown user -> FK fk_comments_author fails
-- INSERT INTO comments (author_id, discussion_id, body) VALUES (999, 1, 'bad');

-- T7. Reply to a comment that does not exist -> FK fk_comments_parent fails
-- INSERT INTO comments (author_id, issue_id, parent_comment_id, body) VALUES (1, 15, 9999, 'bad');

-- T8. Comment becomes its own parent -> BEFORE UPDATE trigger error
-- UPDATE comments SET parent_comment_id = comment_id WHERE comment_id = 1;

-- T9. Move a comment into locked discussion 3 -> BEFORE UPDATE trigger error
-- UPDATE comments SET discussion_id = 3 WHERE comment_id = 1;

-- =====================================================================
-- SECTION 7: FOREIGN KEYS TO ADD LATER (after Modules 3 & 4 are merged)
-- First delete the dummy rows above or replace them with real ids.
-- Confirm PK names/types (INT) with Module 3 and 4 owners.
-- =====================================================================

-- ALTER TABLE discussions
--     ADD CONSTRAINT fk_discussions_repo
--     FOREIGN KEY (repo_id) REFERENCES repositories(repo_id);

-- ALTER TABLE comments
--     ADD CONSTRAINT fk_comments_issue
--     FOREIGN KEY (issue_id) REFERENCES issues(issue_id);

-- ALTER TABLE comments
--     ADD CONSTRAINT fk_comments_pr
--     FOREIGN KEY (pr_id) REFERENCES pull_requests(pr_id);

-- =====================================================================
-- END OF MODULE 6
-- =====================================================================
