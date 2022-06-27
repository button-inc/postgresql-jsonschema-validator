begin;

select * from no_plan();

create temporary table test_case(test_case jsonb);
\copy test_case(test_case) from program 'sed ''s/\\/\\\\/g'' <test-cases/tests/draft7/required.json | tr -d ''\n''';

select has_function('validate_json', ARRAY['jsonb', 'jsonb'], 'the validate_json function exists');

CREATE OR REPLACE FUNCTION my_tests(
) RETURNS SETOF TEXT AS
$test_suite$
declare
  test_file jsonb;
  test_suite jsonb;
  test jsonb;
begin
  for test_file in select test_case from test_case
  loop
    for test_suite in select * from jsonb_array_elements(test_file)
    loop
      for test in select * from jsonb_array_elements(test_suite->'tests')
      loop
        if test->'valid' then
          return next is(
            (select count(*) from validate_json(test->'data', test_suite->'schema')),
            0::bigint,
            test->>'description'
          );
        else
          return next isnt(
            (select count(*) from validate_json(test->'data', test_suite->'schema')),
            0::bigint,
            test->>'description'
          );
        end if;
      end loop;
    end loop;
  end loop;
end
$test_suite$ language 'plpgsql';

select * from my_tests();


select * from finish();

rollback;
