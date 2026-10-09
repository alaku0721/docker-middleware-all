-- 首次启动时自动执行的初始化脚本（仅数据库为空时执行一次）
CREATE TABLE IF NOT EXISTS demo.users (
  id INT PRIMARY KEY AUTO_INCREMENT,
  name VARCHAR(50) NOT NULL,
  email VARCHAR(100),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO demo.users (name, email) VALUES
  ('alice', 'alice@example.com'),
  ('bob', 'bob@example.com');
