-- RPC: Cancel queued find-rider offers (delete pending delivery_offers for this delivery + riders).
-- Matches table: public.delivery_offers (delivery_id uuid, rider_id uuid, status text).
-- SECURITY DEFINER so it works even when RLS blocks direct DELETE.
-- Run once in Supabase Dashboard → SQL Editor.

create or replace function public.cancel_find_rider_offers(
  p_delivery_id uuid,
  p_rider_ids uuid[]
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if array_length(p_rider_ids, 1) is null or array_length(p_rider_ids, 1) = 0 then
    return;
  end if;
  delete from public.delivery_offers
  where delivery_id = p_delivery_id
    and rider_id = any(p_rider_ids)
    and status = 'pending';
end;
$$;

-- Allow the authenticated and anon roles to call it (merchant app uses anon or auth).
grant execute on function public.cancel_find_rider_offers(uuid, uuid[]) to anon;
grant execute on function public.cancel_find_rider_offers(uuid, uuid[]) to authenticated;

comment on function public.cancel_find_rider_offers(uuid, uuid[]) is
  'Deletes pending delivery_offers for the given delivery_id and rider_ids. Used when merchant cancels find rider.';
