drop table sprints if exists
CREATE TABLE sprints (
    sprint_id INT PRIMARY KEY,
    sprint_name VARCHAR(50),
    team VARCHAR(50),
    sprint_number INT,
    start_date DATE,
    end_date DATE,
    release_version VARCHAR(20)
)

drop table modules if exists
CREATE TABLE modules (
    module_id INT PRIMARY KEY,
    module_name VARCHAR(50),
    team VARCHAR(50),
    criticality VARCHAR(20)
)

drop table defects if exists
CREATE TABLE defects (
    defect_id INT PRIMARY KEY,
    sprint_id INT REFERENCES sprints(sprint_id),
    module_id INT REFERENCES modules(module_id),
    severity VARCHAR(20),
    status VARCHAR(20),
    detected_in VARCHAR(20),
    found_in_prod BOOLEAN,
    days_to_fix INT,
    detection_date DATE
)

drop table test_execution if exists
CREATE TABLE test_execution (
    execution_id INT PRIMARY KEY,
    sprint_id INT REFERENCES sprints(sprint_id),
    module_id INT REFERENCES modules(module_id),
    total_cases INT,
    passed INT,
    failed INT,
    blocked INT,
    test_coverage_pct FLOAT
)

drop table sprint_module_summary if exists
CREATE TABLE sprint_module_summary (
    summary_id INT PRIMARY KEY,
    sprint_id INT REFERENCES sprints(sprint_id),
    module_id INT REFERENCES modules(module_id),
    team VARCHAR(50),
    total_defects INT,
    critical_defects INT,
    leaked_defects INT,
    open_defects INT,
    fixed_defects INT,
    total_cases INT,
    passed INT,
    failed INT,
    blocked INT,
    test_coverage_pct FLOAT
)


-- Verifying NULL values in days_to_fix: Nulls belong to 'Open' defects and defects 'Leaked to Prod' — both unfixed. Not a data error.
select status, count(*)
from defects
where days_to_fix is null
group by status


/* SECTION 1: PROBLEM VALIDATION
1. Business Question: Is defect leakage increasing over time? */

-- Query 1: Sprint-wise Defect Leakage Trend
select s2.sprint_number,
    sum(leaked_defects) as leaked_defects,
    sum(total_defects) as total_defects,
    round(sum(leaked_defects)*100.0/sum(total_defects),2) as leakage_rate
from sprint_module_summary s1
join sprints s2
on s1.sprint_id = s2.sprint_id
group by s2.sprint_number
order by s2.sprint_number;


/* SECTION 2: IDENTIFY HIGH-RISK TEAMS
Hypothesis: Certain teams contribute more leakage */

-- Query 2: Team-wise Defect Leakage Rate
select team,
       sum(leaked_defects) as leaked_defects,
       sum(total_defects) as total_defects,
       round(sum(leaked_defects)*100.0/sum(total_defects),2) as leakage_rate
from sprint_module_summary
group by team
order by leakage_rate desc;


/* SECTION 3: IDENTIFY HIGH-RISK MODULES
Hypothesis: Certain modules are driving leakage. */

-- Query 3: Module-wise Defect Leakage Rate
select m.module_name,
       sum(leaked_defects) as leaked_defects,
       sum(total_defects) as total_defects,
       round(sum(leaked_defects)*100.0/sum(total_defects),2) as leakage_rate
from sprint_module_summary s
join modules m
on s.module_id = m.module_id
group by m.module_name
order by leakage_rate desc;


/* SECTION 4: ROOT CAUSE ANALYSIS – CRITICAL DEFECTS
Hypothesis: Critical defects are contributing to leakage. */

-- Query 4: Severity Distribution
select severity,
       count(*) as defects_count,
       round(count(*)*100.0/sum(count(*)) over(),2) as defects_percentage
from defects
group by severity
order by defects_count desc;


-- Query 5: Critical Defects by Team
select m.team,
       count(*) as defects_count,
       round(count(*)*100.0/sum(count(*)) over(),2) as defects_percentage
from defects d
join modules m
on d.module_id = m.module_id
where d.severity = 'Critical'
group by m.team
order by defects_count desc;


/* SECTION 5: ROOT CAUSE ANALYSIS – FIX RATE
Hypothesis: Low fix rates contribute to leakage. */

-- Query 6: Team-wise Fix Rate
select team,
       round(sum(fixed_defects)*100.0/sum(total_defects),2) as fix_rate
from sprint_module_summary
group by team
order by fix_rate;


-- Query 7: Payment Gateway Core Sprint-wise Fix Rate
select s1.sprint_number,
       sum(fixed_defects) as fixed_defects,
       sum(total_defects) as total_defects,
       round(sum(fixed_defects)*100.0/sum(total_defects),2) as fix_rate
from sprints s1
join sprint_module_summary s2
on s1.sprint_id = s2.sprint_id
join modules m
on s2.module_id = m.module_id
where m.module_name = 'Payment Gateway Core'
group by s1.sprint_number
order by sprint_number;


/* SECTION 6: ROOT CAUSE ANALYSIS – TEST COVERAGE
Hypothesis: Low test coverage contributes to leakage. */

-- Query 8: Module-wise Test Coverage
select m.module_name,
       round(cast(avg(test_coverage_pct) as numeric)*100,2) as avg_test_coverage
from modules m
join test_execution t
on m.module_id = t.module_id
group by m.module_name
order by avg_test_coverage desc;


/* SECTION 7: ROOT CAUSE ANALYSIS – OPEN DEFECT BACKLOG
Hypothesis: Open defects contribute to leakage. */

-- Query 9: Open Defects by Team
select team,
       sum(open_defects) as open_defects
from sprint_module_summary
group by team
order by open_defects desc;


-- Query 10: Open & Leaked Defect Ownership
select d.status,
       m.team,
       count(*) as defects_count
from defects d
join modules m
on d.module_id = m.module_id
where d.status in ('Open','Leaked_to_Prod')
group by d.status, m.team
order by d.status, defects_count desc;


/* SECTION 8: QUALITY HEALTH OVERVIEW
Purpose: Understand overall defect status distribution. */

-- Query 11: Overall Defect Status Distribution
select status,
       count(*) as defects_count,
       round(count(*)*100.0/sum(count(*)) over(),2) as defects_pct
from defects
group by status
order by defects_pct desc;


/* SECTION 9: RELEASE READINESS MODEL
Purpose: Build release decision framework.*/

-- Query 12: Sprint KPI Construction
create view sprint_kpis as
select sprint_number,
       round(cast(avg(test_coverage_pct)*100.0 as numeric),2) as test_coverage,
       round(sum(fixed_defects)*100.0/sum(total_defects),2) as fix_rate,
       round(sum(leaked_defects)*100.0/sum(total_defects),2) as leakage_rate,
       round(sum(critical_defects)*100.0/sum(total_defects),2) as critical_pct,
       round(sum(open_defects)*100.0/sum(total_defects),2) as open_defects_rate
from sprint_module_summary s1
join sprints s2
on s1.sprint_id = s2.sprint_id
group by sprint_number
order by sprint_number;

select * from sprint_kpis;


-- Query 13: Release Readiness Score Calculation
create view sprint_readiness as
select sprint_number,
       test_coverage,
       fix_rate,
       critical_pct,
       open_defects_rate,
       round(
            (test_coverage * 0.30) +
            (fix_rate * 0.35) +
            ((100 - critical_pct) * 0.20) +
            ((100 - open_defects_rate) * 0.15),
       2) as release_readiness_score
from sprint_kpis
order by sprint_number;

select * from sprint_readiness;



-- Query 14: Release Decision Classification
select *,
       case
           when release_readiness_score >= 80 then 'Go'
           when release_readiness_score >= 70 then 'Caution'
           else 'No-Go'
       end as release_decision
from sprint_readiness
order by sprint_number;

