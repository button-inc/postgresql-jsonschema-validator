begin;

create or replace function validate_json(json_data jsonb, json_schema jsonb)
returns setof text as
$function$
begin
end;
$function$ language 'plpgsql' stable;

commit;
