CREATE DATABASE IF NOT EXISTS customer_analysis;

USE customer_analysis;

CREATE TABLE IF NOT EXISTS transactions_info (
    date_new VARCHAR(20),
    Id_check BIGINT,
    ID_client BIGINT,
    Count_products DECIMAL(12,3),
    Sum_payment DECIMAL(15,2)
);
USE customer_analysis;


RENAME TABLE
`customer_info.xlsx - query_for_abt_customerinfo_0002`
TO customer_info;

DROP VIEW IF EXISTS v_checks;

CREATE VIEW v_checks AS
SELECT
    t.ID_client,
    t.Id_check,
    STR_TO_DATE(
        MIN(t.date_new),
        '%d/%m/%Y'
    ) AS purchase_date,
    SUM(t.Sum_payment) AS check_amount,
    SUM(t.Count_products) AS products_count,
    COALESCE(
        NULLIF(UPPER(TRIM(c.Gender)), ''),
        'NA'
    ) AS gender,
    c.Age AS age
FROM transactions_info t
LEFT JOIN customer_info c
    ON t.ID_client = c.Id_client
GROUP BY
    t.ID_client,
    t.Id_check,
    c.Gender,
    c.Age;

LOAD DATA LOCAL INFILE 'C:/SQL/transactions_info.csv'
INTO TABLE transactions_info
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(date_new, Id_check, ID_client, Count_products, Sum_payment);
SELECT COUNT(*) AS total_rows
FROM transactions_info;


USE customer_analysis;



   
    
    SELECT *
FROM v_checks
LIMIT 20;


WITH monthly_activity AS (
    SELECT
        ID_client,
        COUNT(DISTINCT DATE_FORMAT(
            purchase_date, '%Y-%m'
        )) AS active_months
    FROM v_checks
    WHERE purchase_date >= '2015-06-01'
      AND purchase_date < '2016-06-01'
    GROUP BY ID_client
),
client_stats AS (
    SELECT
        ID_client,
        COUNT(*) AS total_operations,
        SUM(check_amount) AS total_spent,
        ROUND(AVG(check_amount), 2) AS avg_check,
        ROUND(SUM(check_amount) / 12, 2)
            AS avg_monthly_spent
    FROM v_checks
    WHERE purchase_date >= '2015-06-01'
      AND purchase_date < '2016-06-01'
    GROUP BY ID_client
)
SELECT
    s.ID_client,
    m.active_months,
    s.avg_check,
    s.avg_monthly_spent,
    s.total_operations,
    ROUND(s.total_spent, 2) AS total_spent
FROM client_stats s
JOIN monthly_activity m
    ON s.ID_client = m.ID_client
WHERE m.active_months = 12
ORDER BY s.total_spent DESC;


##Средний чек, количество операций, количество клиентов и доли
WITH monthly AS (
    SELECT
        DATE_FORMAT(
            purchase_date, '%Y-%m'
        ) AS month,
        COUNT(*) AS operations,
        COUNT(DISTINCT ID_client)
            AS active_clients,
        SUM(check_amount) AS total_amount,
        AVG(check_amount) AS avg_check
    FROM v_checks
    WHERE purchase_date >= '2015-06-01'
      AND purchase_date < '2016-06-01'
    GROUP BY DATE_FORMAT(
        purchase_date, '%Y-%m'
    )
)
SELECT
    month,
    ROUND(avg_check, 2) AS avg_check,
    operations,
    active_clients,
    ROUND(AVG(operations) OVER (), 2)
        AS avg_operations_per_month,
    ROUND(AVG(active_clients) OVER (), 2)
        AS avg_clients_per_month,
    ROUND(total_amount, 2) AS total_amount,
    ROUND(
        100.0 * operations /
        SUM(operations) OVER (), 2
    ) AS operations_share_pct,
    ROUND(
        100.0 * total_amount /
        SUM(total_amount) OVER (), 2
    ) AS amount_share_pct
FROM monthly
ORDER BY month;


##Соотношение мужчин, женщин и клиентов без указанного пола
WITH gender_month AS (
    SELECT
        DATE_FORMAT(
            purchase_date, '%Y-%m'
        ) AS month,
        gender,
        COUNT(DISTINCT ID_client)
            AS clients_count,
        COUNT(*) AS operations,
        SUM(check_amount) AS total_spent
    FROM v_checks
    WHERE purchase_date >= '2015-06-01'
      AND purchase_date < '2016-06-01'
    GROUP BY
        DATE_FORMAT(purchase_date, '%Y-%m'),
        gender
)
SELECT
    month,
    gender,
    clients_count,
    operations,
    ROUND(total_spent, 2) AS total_spent,
    ROUND(
        100.0 * clients_count /
        SUM(clients_count) OVER (
            PARTITION BY month
        ), 2
    ) AS clients_share_pct,
    ROUND(
        100.0 * total_spent /
        NULLIF(
            SUM(total_spent) OVER (
                PARTITION BY month
            ), 0
        ), 2
    ) AS spending_share_pct
FROM gender_month
ORDER BY month, gender;


##Общие показатели за год
WITH age_data AS (
    SELECT
        CASE
            WHEN age IS NULL OR age <= 0
                THEN 'NA'
            ELSE CONCAT(
                FLOOR(age / 10) * 10,
                '-',
                FLOOR(age / 10) * 10 + 9
            )
        END AS age_group,
        CASE
            WHEN age IS NULL OR age <= 0
                THEN -1
            ELSE FLOOR(age / 10)
        END AS age_sort,
        ID_client,
        check_amount
    FROM v_checks
    WHERE purchase_date >= '2015-06-01'
      AND purchase_date < '2016-06-01'
),
age_stats AS (
    SELECT
        age_group,
        age_sort,
        COUNT(*) AS operations,
        COUNT(DISTINCT ID_client)
            AS clients_count,
        SUM(check_amount) AS total_amount,
        AVG(check_amount) AS avg_check
    FROM age_data
    GROUP BY age_group, age_sort
)
SELECT
    age_group,
    clients_count,
    operations,
    ROUND(total_amount, 2) AS total_amount,
    ROUND(avg_check, 2) AS avg_check,
    ROUND(
        100.0 * operations /
        SUM(operations) OVER (), 2
    ) AS operations_pct,
    ROUND(
        100.0 * total_amount /
        SUM(total_amount) OVER (), 2
    ) AS amount_pct
FROM age_stats
ORDER BY age_sort;



##Поквартальный анализ возрастных групп
WITH quarterly_data AS (
    SELECT
        CASE
            WHEN age IS NULL OR age <= 0
                THEN 'NA'
            ELSE CONCAT(
                FLOOR(age / 10) * 10,
                '-',
                FLOOR(age / 10) * 10 + 9
            )
        END AS age_group,
        CASE
            WHEN age IS NULL OR age <= 0
                THEN -1
            ELSE FLOOR(age / 10)
        END AS age_sort,
        CONCAT(
            'Q',
            FLOOR(
                TIMESTAMPDIFF(
                    MONTH,
                    '2015-06-01',
                    purchase_date
                ) / 3
            ) + 1
        ) AS quarter,
        ID_client,
        check_amount
    FROM v_checks
    WHERE purchase_date >= '2015-06-01'
      AND purchase_date < '2016-06-01'
),
quarterly_stats AS (
    SELECT
        age_group,
        age_sort,
        quarter,
        COUNT(*) AS operations,
        COUNT(DISTINCT ID_client)
            AS clients_count,
        SUM(check_amount) AS total_amount,
        AVG(check_amount) AS avg_check
    FROM quarterly_data
    GROUP BY age_group, age_sort, quarter
)
SELECT
    quarter,
    age_group,
    clients_count,
    operations,
    ROUND(total_amount, 2) AS total_amount,
    ROUND(avg_check, 2) AS avg_check,
    ROUND(operations / 3, 2)
        AS avg_operations_month,
    ROUND(total_amount / 3, 2)
        AS avg_amount_month,
    ROUND(
        100.0 * operations /
        SUM(operations) OVER (
            PARTITION BY quarter
        ), 2
    ) AS operations_pct,
    ROUND(
        100.0 * total_amount /
        SUM(total_amount) OVER (
            PARTITION BY quarter
        ), 2
    ) AS amount_pct
FROM quarterly_stats
ORDER BY quarter, age_sort;



##Проверка правильности результатов
SELECT
    COUNT(*) AS total_checks,
    COUNT(DISTINCT ID_client) AS clients,
    MIN(purchase_date) AS first_date,
    MAX(purchase_date) AS last_date
FROM v_checks
WHERE purchase_date >= '2015-06-01'
  AND purchase_date < '2016-06-01';