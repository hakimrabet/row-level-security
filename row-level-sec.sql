CREATE TABLE users
(
    id   SERIAL PRIMARY KEY,
    name TEXT
);

CREATE TABLE departments
(
    id   SERIAL PRIMARY KEY,
    name TEXT
);

CREATE TABLE roles
(
    id   SERIAL PRIMARY KEY,
    name TEXT
);

CREATE TABLE acl
(
    user_       INT REFERENCES users,
    department_ INT REFERENCES departments,
    role_       INT REFERENCES roles
);

CREATE TYPE viewkind AS ENUM ('own', 'hierarchy', 'all');

CREATE TABLE products
(
    id     SERIAL PRIMARY KEY,
    owner_ INT REFERENCES users,
    name   TEXT,
    data   TEXT
);

-- Create users
INSERT INTO users
VALUES (1, 'alice'),
       (2, 'amy'),
       (3, 'billy'),
       (4, 'bob'),
       (5, 'caitlin'),
       (6, 'charlie');

INSERT INTO departments
VALUES (1, 'it'),
       (2, 'finance');

INSERT INTO roles
values (1, 'admin'),
       (2, 'user');

-- Create objects belonging to owner alice, amy
INSERT INTO products
VALUES (1, 1, 'apples', 'this is apple'),
       (2, 2, 'oranges', 'this is oranges');

-- Create objects belonging to owner billy
INSERT INTO products
VALUES (3, 3, 'bananna', 'bananas'),
       (4, 3, 'ananas', 'ananas');

-- alice and amy can access department it
INSERT INTO acl
VALUES (1, 1, 1),
       (2, 1, 2);

-- billy and bob can access group finance
INSERT INTO acl
VALUES (3, 2, 1),
       (4, 2, 2);

-- caitlin and charlie can access groups it and finance
INSERT INTO acl
VALUES (5, 1, 2),
       (5, 2, 2),
       (6, 1, 2),
       (6, 2, 2);

---working---------
CREATE VIEW allowed AS
SELECT products.name    as product_name,
       products.data,
       departments.name as department,
       roles.id       as role,
       users.name       as owner
FROM products
         INNER JOIN acl ON acl.user_ = products.owner_
         INNER JOIN departments on departments.id = acl.department_
         INNER JOIN roles ON roles.id = acl.role_
         INNER JOIN users ON users.id = acl.user_;
---------------------------------------------------
select *
from allowed
where owner = 'alice';

select *
from allowed
where department = 'it';

create function get_record("user" text, view text)
    RETURNS TABLE
            (
                product_name  text,
                products_data text,
                department    text,
                role          INT,
                owner         TEXT
            )
as
$$
begin
    return query
        select *
        from allowed
        where case
                  when view = 'own' then allowed.owner = user
                  when view = 'hierarchy' then (allowed.department IN (select d.name
                                                                       from users
                                                                                INNER JOIN acl a on users.id = a.user_
                                                                                INNER JOIN departments d on a.department_ = d.id
                                                                       where users.name = user) and
                                                allowed.role::INT > (select a.role_
                                                                     from users
                                                                              INNER JOIN acl a on users.id = a.user_
                                                                     where name = user)) OR
                                               (allowed.owner = user)
                  when view = 'all' then allowed.department IN (select d.name
                                                                from users
                                                                         INNER JOIN acl a on users.id = a.user_
                                                                         INNER JOIN departments d on a.department_ = d.id
                                                                where users.name = user)
                  END;
END
$$ language plpgsql;

SELECT * from get_record('amy','all');

-----------------working-------------------------------------------
CREATE OR REPLACE function get_record(username text, view text)
    RETURNS SETOF allowed
as
$$
begin
    case view
        when 'own' then return query select *
                                     from allowed
                                     where allowed.owner = username;
        when 'hierarchy' then return query select *
                                           from allowed
                                           where (allowed.department IN (select d.name
                                                                         from users
                                                                                  INNER JOIN acl a on users.id = a.user_
                                                                                  INNER JOIN departments d on a.department_ = d.id
                                                                         where users.name = username) and
                                                  allowed.role::INT > (select a.role_
                                                                       from users
                                                                                INNER JOIN acl a on users.id = a.user_
                                                                       where name = username))
                                              OR (allowed.owner = username);
        when 'all' then return query select *
                                     from allowed
                                     where allowed.department IN (select d.name
                                                                  from users
                                                                           INNER JOIN acl a on users.id = a.user_
                                                                           INNER JOIN departments d on a.department_ = d.id
                                                                  where users.name = username);
        END CASE;
END
$$ language plpgsql;

SELECT * from get_record('alice','own');


CREATE VIEW allowed2 AS
SELECT products.name    as product_name,
       products.data,
       departments.id as department,
       roles.id       as role,
       users.name       as owner
FROM products
         INNER JOIN acl ON acl.user_ = products.owner_
         INNER JOIN departments on departments.id = acl.department_
         INNER JOIN roles ON roles.id = acl.role_
         INNER JOIN users ON users.id = acl.user_ ;

select * from allowed2;

CREATE OR REPLACE function get_record_optimize(username text, view text)
    RETURNS SETOF allowed2
as
$$
begin
    case view
        when 'own' then return query select *
                                     from allowed2
                                     where (view = 'own' AND allowed2.owner = username)
                                        OR ();
        when 'hierarchy' then return query select *
                                           from allowed2
                                           where (allowed2.department IN (select Distinct a.department_
                                                                         from users
                                                                                  INNER JOIN acl a on users.id = a.user_
                                                                         where users.name = username) and
                                                  allowed2.role > (select distinct a.role_
                                                                       from users
                                                                                INNER JOIN acl a on users.id = a.user_
                                                                       where name = username))
                                              OR (allowed2.owner = username);
        when 'all' then return query select *
                                     from allowed2
                                     where allowed2.department IN (select distinct a.department_
                                                                  from users
                                                                           INNER JOIN acl a on users.id = a.user_
                                                                  where users.name = username);
        END CASE;
END
$$ language plpgsql;

explain SELECT * from get_record('alice','own');
explain analyze SELECT * from get_record('alice','hierarchy');

explain SELECT * from get_record_optimize('alice','own');
explain analyze SELECT * from get_record_optimize('alice','hierarchy');
