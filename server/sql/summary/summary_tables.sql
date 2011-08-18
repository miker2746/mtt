DROP TABLE summary_mpi_install;
DROP TABLE summary_test_build;
DROP TABLE summary_test_run;
DROP TABLE summary_base;

CREATE TABLE summary_base (
    -- select date_trunc('hour', now()) --
    start_timestamp   timestamp without time zone NOT NULL DEFAULT now() - interval '24 hours',
    end_timestamp     timestamp without time zone NOT NULL DEFAULT now() - interval '24 hours',

    --
    -- Submit
    --
    submit_http_username              varchar(16)  NOT NULL DEFAULT 'bogus',

    --
    -- Compute Cluster
    --
    compute_cluster_platform_name     varchar(128) NOT NULL DEFAULT 'bogus',
    compute_cluster_platform_hardware varchar(128) NOT NULL DEFAULT 'bogus',
    compute_cluster_os_name           varchar(128) NOT NULL DEFAULT 'bogus',

    --
    -- MPI Get
    --
    mpi_get_mpi_name       varchar(64) NOT NULL DEFAULT 'bogus',
    mpi_get_mpi_version    varchar(128) NOT NULL DEFAULT 'bogus',

    --
    -- MPI Install Configure Args
    --
    mpi_install_configure_args_bitness   bit(6) NOT NULL DEFAULT B'000000',
    mpi_install_configure_args_endian    bit(2) NOT NULL DEFAULT B'00',

    --
    -- Compiler
    --
    compiler_compiler_name      varchar(64) NOT NULL DEFAULT 'bogus',
    compiler_compiler_version   varchar(64) NOT NULL DEFAULT 'bogus',

    --
    -- Test Suite
    --
    test_suites_suite_name   varchar(32) DEFAULT 'bogus',

    --
    -- Test Run
    --
    np                  smallint DEFAULT (-38),

    pass smallint NOT NULL DEFAULT '0',
    fail smallint NOT NULL DEFAULT '0'
);

CREATE TABLE summary_mpi_install (
    summary_mpi_install_id      serial,
    -- ********** --
    PRIMARY KEY (summary_mpi_install_id)
) INHERITS(summary_base);

CREATE TABLE summary_test_build (
    summary_test_build_id      serial,
    -- ********** --
    PRIMARY KEY (summary_test_build_id)
) INHERITS(summary_base);

CREATE TABLE summary_test_run (
    summary_test_run_id      serial,

    skip smallint NOT NULL DEFAULT '0',
    timeout smallint NOT NULL DEFAULT '0',
    perf smallint NOT NULL DEFAULT '0',

    -- ********** --
    PRIMARY KEY (summary_test_run_id)
) INHERITS(summary_base);

-- --------------------------------------------------
-- --------------------------------------------------
-- --------------------------------------------------
CREATE OR REPLACE FUNCTION update_summary_table() RETURNS TRIGGER AS $update_summary_table$
    DECLARE
        -- Submit
        tmp_http_username varchar(16);
        -- Compute Cluster
        tmp_platform_name varchar(128);
        tmp_platform_hardware varchar(128);
        tmp_os_name varchar(128);
        -- MPI Get
        tmp_mpi_name varchar(64);
        tmp_mpi_version varchar(128);
        -- MPI Install Configure Args
        tmp_bitness  bit(6);
        tmp_endian   bit(2);
        -- Compiler
        tmp_compiler_name varchar(64);
        tmp_compiler_version varchar(64);
        tmp_build_compiler_name varchar(64);
        tmp_build_compiler_version varchar(64);
        -- Test Suite
        tmp_suite_name varchar(32);
        -- Test Run
        tmp_np smallint;
        -- Other
        tmp_timestamp timestamp without time zone;
        tmp_timestamp_end timestamp without time zone;
        -- Success/Fail/...
        tmp_pass smallint;
        tmp_fail smallint;
        tmp_skip smallint;
        tmp_timeout smallint;
        tmp_perf smallint;
        -- Index in summary table
        tmp_mod_idx int;
        -- Summary Table Name
        name_summary varchar(128);
    BEGIN
        --name_summary = ('summary_' || TG_TABLE_NAME);
        --RAISE NOTICE 'Relation (%) (%)', TG_TABLE_NAME, name_summary;
        IF( TG_TABLE_NAME ~* '^mpi_install') THEN
            name_summary = 'summary_mpi_install';
        ELSIF (TG_TABLE_NAME ~* '^test_build') THEN
            name_summary = 'summary_test_build';
        ELSIF (TG_TABLE_NAME ~* '^test_run') THEN
            name_summary = 'summary_test_run';
        END IF;
        --RAISE NOTICE 'Relation (%) (%)', TG_TABLE_NAME, name_summary;

        IF( TG_TABLE_NAME !~* '^mpi_install' AND
            TG_TABLE_NAME !~* '^test_build' AND
            TG_TABLE_NAME !~* '^test_run' ) THEN
            RAISE EXCEPTION 'Operating on an Invalid Relation (%s)', TG_TABLE_NAME;
        END IF;
        
        --
        -- Submit
        --
        SELECT http_username
            INTO tmp_http_username
            FROM submit
            WHERE submit_id = NEW.submit_id;
        --RAISE NOTICE 'Submit (% = %)', NEW.submit_id, tmp_http_username;

        --
        -- Compute Cluster
        --
        SELECT platform_name, platform_hardware, os_name
            INTO tmp_platform_name, tmp_platform_hardware, tmp_os_name
            FROM compute_cluster
            WHERE compute_cluster_id = NEW.compute_cluster_id;
        --RAISE NOTICE 'CC (% = %, %, %)', NEW.compute_cluster_id, tmp_platform_name, tmp_platform_hardware, tmp_os_name;

        --
        -- MPI Get
        --
        SELECT mpi_name, mpi_version
            INTO tmp_mpi_name, tmp_mpi_version
            FROM mpi_get
            WHERE mpi_get_id = NEW.mpi_get_id;
        --RAISE NOTICE 'MPI (% = %, %)', NEW.compute_cluster_id, tmp_mpi_name, tmp_mpi_version;

        --
        -- MPI Install Configure Args
        --
        SELECT bitness, endian
            INTO tmp_bitness, tmp_endian
            FROM mpi_install_configure_args
            WHERE mpi_install_configure_id = NEW.mpi_install_configure_id;
        --RAISE NOTICE 'Conf (% = %, %)', NEW.mpi_install_configure_id, tmp_bitness, tmp_endian;

        --
        -- Compiler
        --
        SELECT compiler_name, compiler_version
            INTO tmp_compiler_name, tmp_compiler_version
            FROM compiler
            WHERE compiler_id = NEW.mpi_install_compiler_id;
        --RAISE NOTICE 'Comp (% = %, %)', NEW.mpi_install_compiler_id, tmp_compiler_name, tmp_compiler_version;
        IF (TG_TABLE_NAME ~* '^test_build' OR TG_TABLE_NAME ~* '^test_run' ) THEN
            SELECT compiler_name, compiler_version
                INTO tmp_build_compiler_name, tmp_build_compiler_version
                FROM compiler
                WHERE compiler_id = NEW.test_build_compiler_id;
            --RAISE NOTICE 'Comp (% = %, %)', NEW.mpi_install_compiler_id, tmp_compiler_name, tmp_compiler_version;
        END IF;

        --
        -- Test Suite
        --
        IF( TG_TABLE_NAME ~* '^test_build' OR TG_TABLE_NAME ~* '^test_run' ) THEN
            SELECT suite_name
                INTO tmp_suite_name
                FROM test_suites
                WHERE test_suite_id = NEW.test_suite_id;
            --RAISE NOTICE 'Suite (% = %)', NEW.test_suite_id, tmp_suite_name;
        ELSE
            tmp_suite_name = NULL;
            --RAISE NOTICE 'Suite (%)', tmp_suite_name;
        END IF;

        --
        -- Test Run
        --
        IF( TG_TABLE_NAME ~* '^test_run' ) THEN
            tmp_np = NEW.np;
        ELSE
            tmp_np = -1;
        END IF;
        --RAISE NOTICE 'NP (%)', tmp_np;

        --
        -- Success/Failure/Other
        --
        tmp_pass = 0;
        tmp_fail = 0;
        tmp_skip = 0;
        tmp_timeout = 0;
        tmp_perf = 0;
        IF (NEW.test_result = 1) THEN
            tmp_pass = 1;
            --RAISE NOTICE 'Test (% = pass)', NEW.test_result;
        ELSIF (NEW.test_result = 0) THEN
            tmp_fail = 1;
            --RAISE NOTICE 'Test (% = fail)', NEW.test_result;
        ELSIF (NEW.test_result = 2) THEN
            tmp_skip = 1;
            --RAISE NOTICE 'Test (% = skip)', NEW.test_result;
        ELSIF (NEW.test_result = 3) THEN
            tmp_timeout = 1;
            --RAISE NOTICE 'Test (% = timeout)', NEW.test_result;
        END IF;
        IF( TG_TABLE_NAME ~* '^test_run' ) THEN
            IF (NEW.performance_id > 0) THEN
                tmp_perf = 1;
                --RAISE NOTICE 'Test (% = perf)', NEW.test_result;
            END IF;
        END IF;
        --RAISE NOTICE 'Test (% / % / % / % / %)', tmp_pass, tmp_fail, tmp_skip, tmp_timeout, tmp_perf;

        --
        -- Timestamp
        --
        tmp_timestamp = date_trunc('hour', NEW.start_timestamp);
        tmp_timestamp_end = date_trunc('hour', (NEW.start_timestamp + interval '1 hours'));
        --RAISE NOTICE 'TIME (% = % to %)', NEW.start_timestamp, tmp_timestamp, tmp_timestamp_end;

        --
        -- Test for existing row
        --
        IF( TG_TABLE_NAME ~* '^mpi_install' ) THEN
            SELECT summary_mpi_install_id INTO tmp_mod_idx
                FROM summary_mpi_install
                WHERE
                    start_timestamp = tmp_timestamp AND
                    end_timestamp = tmp_timestamp_end AND
                    submit_http_username = tmp_http_username AND
                    compute_cluster_platform_name = tmp_platform_name AND
                    compute_cluster_platform_hardware = tmp_platform_hardware AND
                    compute_cluster_os_name = tmp_os_name AND
                    mpi_get_mpi_name = tmp_mpi_name AND
                    mpi_get_mpi_version = tmp_mpi_version AND
                    mpi_install_configure_args_bitness = tmp_bitness AND
                    mpi_install_configure_args_endian = tmp_endian AND
                    compiler_compiler_name = tmp_compiler_name AND
                    compiler_compiler_version = tmp_compiler_version
            ;
        ELSIF (TG_TABLE_NAME ~* '^test_build' ) THEN
            SELECT summary_test_build_id INTO tmp_mod_idx
                FROM summary_test_build
                WHERE
                    start_timestamp = tmp_timestamp AND
                    end_timestamp = tmp_timestamp_end AND
                    submit_http_username = tmp_http_username AND
                    compute_cluster_platform_name = tmp_platform_name AND
                    compute_cluster_platform_hardware = tmp_platform_hardware AND
                    compute_cluster_os_name = tmp_os_name AND
                    mpi_get_mpi_name = tmp_mpi_name AND
                    mpi_get_mpi_version = tmp_mpi_version AND
                    mpi_install_configure_args_bitness = tmp_bitness AND
                    mpi_install_configure_args_endian = tmp_endian AND
                    compiler_compiler_name = tmp_compiler_name AND
                    compiler_compiler_version = tmp_compiler_version AND
                    test_suites_suite_name = tmp_suite_name
            ;
        ELSIF (TG_TABLE_NAME ~* '^test_run' ) THEN
            SELECT summary_test_run_id INTO tmp_mod_idx
                FROM summary_test_run
                WHERE
                    start_timestamp = tmp_timestamp AND
                    end_timestamp = tmp_timestamp_end AND
                    submit_http_username = tmp_http_username AND
                    compute_cluster_platform_name = tmp_platform_name AND
                    compute_cluster_platform_hardware = tmp_platform_hardware AND
                    compute_cluster_os_name = tmp_os_name AND
                    mpi_get_mpi_name = tmp_mpi_name AND
                    mpi_get_mpi_version = tmp_mpi_version AND
                    mpi_install_configure_args_bitness = tmp_bitness AND
                    mpi_install_configure_args_endian = tmp_endian AND
                    compiler_compiler_name = tmp_compiler_name AND
                    compiler_compiler_version = tmp_compiler_version AND
                    test_suites_suite_name = tmp_suite_name AND
                    np = tmp_np
            ;
        END IF;
        --RAISE NOTICE 'SELECT (%)', tmp_mod_idx;

        --
        -- Insert (try)
        --
        IF ( tmp_mod_idx IS NULL ) THEN
            --RAISE NOTICE 'Insert New (%)', tmp_mod_idx;
            IF( TG_TABLE_NAME ~* '^mpi_install' ) THEN
                INSERT INTO summary_mpi_install
                    (start_timestamp,
                     end_timestamp,
                     submit_http_username,
                     compute_cluster_platform_name,
                     compute_cluster_platform_hardware,
                     compute_cluster_os_name,
                     mpi_get_mpi_name,
                     mpi_get_mpi_version,
                     mpi_install_configure_args_bitness,
                     mpi_install_configure_args_endian,
                     compiler_compiler_name,
                     compiler_compiler_version,
                     test_suites_suite_name,
                     np,
                     pass,
                     fail
                    ) VALUES (
                     tmp_timestamp,
                     tmp_timestamp_end,
                     tmp_http_username,
                     tmp_platform_name,
                     tmp_platform_hardware,
                     tmp_os_name,
                     tmp_mpi_name,
                     tmp_mpi_version,
                     tmp_bitness,
                     tmp_endian,
                     tmp_compiler_name,
                     tmp_compiler_version,
                     tmp_suite_name,
                     tmp_np,
                     tmp_pass,
                     tmp_fail
                    );
            ELSIF(  TG_TABLE_NAME ~* '^test_build' ) THEN
                INSERT INTO summary_test_build
                    (start_timestamp,
                     end_timestamp,
                     submit_http_username,
                     compute_cluster_platform_name,
                     compute_cluster_platform_hardware,
                     compute_cluster_os_name,
                     mpi_get_mpi_name,
                     mpi_get_mpi_version,
                     mpi_install_configure_args_bitness,
                     mpi_install_configure_args_endian,
                     compiler_compiler_name,
                     compiler_compiler_version,
                     test_suites_suite_name,
                     np,
                     pass,
                     fail
                    ) VALUES (
                     tmp_timestamp,
                     tmp_timestamp_end,
                     tmp_http_username,
                     tmp_platform_name,
                     tmp_platform_hardware,
                     tmp_os_name,
                     tmp_mpi_name,
                     tmp_mpi_version,
                     tmp_bitness,
                     tmp_endian,
                     tmp_compiler_name,
                     tmp_compiler_version,
                     tmp_suite_name,
                     tmp_np,
                     tmp_pass,
                     tmp_fail
                    );
            ELSIF (TG_TABLE_NAME ~* '^test_run' ) THEN
                INSERT INTO summary_test_run
                    (start_timestamp,
                     end_timestamp,
                     submit_http_username,
                     compute_cluster_platform_name,
                     compute_cluster_platform_hardware,
                     compute_cluster_os_name,
                     mpi_get_mpi_name,
                     mpi_get_mpi_version,
                     mpi_install_configure_args_bitness,
                     mpi_install_configure_args_endian,
                     compiler_compiler_name,
                     compiler_compiler_version,
                     test_suites_suite_name,
                     np,
                     pass,
                     fail,
                     skip,
                     timeout,
                     perf
                    ) VALUES (
                     tmp_timestamp,
                     tmp_timestamp_end,
                     tmp_http_username,
                     tmp_platform_name,
                     tmp_platform_hardware,
                     tmp_os_name,
                     tmp_mpi_name,
                     tmp_mpi_version,
                     tmp_bitness,
                     tmp_endian,
                     tmp_compiler_name,
                     tmp_compiler_version,
                     tmp_suite_name,
                     tmp_np,
                     tmp_pass,
                     tmp_fail,
                     tmp_skip,
                     tmp_timeout,
                     tmp_perf
                    );
            END IF;
        ELSE
            --RAISE NOTICE 'Mod Exist  (%)', tmp_mod_idx;
            IF( TG_TABLE_NAME ~* '^mpi_install') THEN
                UPDATE summary_mpi_install
                    SET pass = pass + tmp_pass, fail = fail + tmp_fail
                    WHERE summary_mpi_install_id = tmp_mod_idx;
            ELSIF(  TG_TABLE_NAME ~* '^test_build' ) THEN
                UPDATE summary_test_build
                    SET pass = pass + tmp_pass, fail = fail + tmp_fail
                    WHERE summary_test_build_id = tmp_mod_idx;
            ELSIF (TG_TABLE_NAME ~* '^test_run' ) THEN
                UPDATE summary_test_run
                    SET pass = pass + tmp_pass, fail = fail + tmp_fail,
                    skip = skip + tmp_skip, timeout = timeout + tmp_timeout, perf = perf + tmp_perf
                    WHERE summary_test_run_id = tmp_mod_idx;
            END IF;
        END IF;

        return NULL;
    END;
$update_summary_table$ LANGUAGE plpgsql;

-- CREATE TRIGGER update_summary_table
-- AFTER INSERT ON mpi_install
--     FOR EACH ROW EXECUTE PROCEDURE update_summary_table();

-- CREATE TRIGGER update_summary_table
-- AFTER INSERT ON test_build
--     FOR EACH ROW EXECUTE PROCEDURE update_summary_table();

-- CREATE TRIGGER update_summary_table
-- AFTER INSERT ON test_run
--     FOR EACH ROW EXECUTE PROCEDURE update_summary_table();