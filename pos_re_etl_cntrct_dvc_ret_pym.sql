create table bdl_analytics_sandbox.pos_re_etl_cntrct_dvc_ret_pym as
        select a.subscriberid , last_device_purchased , end_date contract_end_date ,-- snapshotdate retention_lead_snapshotdate, 
         ttl_freq payment_failed_freq,  latest_failed_date latest_failed_payment_date , contract_name ,  stcservicetype ,
         case when DATEDIFF(end_date,a.SnapshotDate) between   0 and 60 then 1 else 0 end as ContractExp60DInd, --- expiring in next 30 days
        case when DATEDIFF(end_date,a.SnapshotDate) between   0 and 30 then 1 else 0 end as ContractExp30DInd, --- expiring in next 30 days
        case when DATEDIFF(end_date,a.SnapshotDate) between -30 and 0  then 1 else 0 end as ContractExprd30DInd, --- expiring in next 30 days
        DATEDIFF(end_date,a.SnapshotDate)  as ContractDays, --- no of days since expiry 
        cast(DATEDIFF(end_date,a.SnapshotDate)/30 as integer) as ContractMths -- no of mo since expiry  
         from (select subscriberid, msisdn, to_date(now()) as SnapshotDate from bdl_analytics_sandbox.ds_churn_postpaiduniverse_new --bdl_ds.ds_churn_factuniversepostpaid where SnapshotDate=from_utc_timestamp(now() ,'Asia/Bahrain') between -1 and 0  --to_date(cast(from_unixtime(unix_timestamp(now() - interval dayofmonth(date_add(now(),0)) days), 'yyyyMMdd') as int)) 
         group by 1,2,3) a
        left join
        (
        SELECT distinct subscriberid , end_date , contract_name , stcservicetype
        from (
        SELECT  T.productid ,stcservicetype,T.msisdn , subscriberid ,
        from_utc_timestamp(T.start_date ,'Asia/Bahrain') start_date , from_utc_timestamp(T.end_date ,'Asia/Bahrain') end_date , contract_name  , -- source ,
        ROW_NUMBER() OVER(PARTITION BY T.msisdn  ORDER BY T.end_date desc) AS rank
                FROM 
                       (SELECT p1.productid AS productid, stcservicetype , producttype , SUBSTRING(a1.login,1,11) AS msisdn, subscriberid ,
                        a1.purchase_startdt AS start_date, a1.purchase_enddt AS end_date,a1.contract_name AS contract_name,'Expired' source  
                        FROM bdl_raw.brm_contractexpired a1 
                        inner join (select subscriberid, msisdn, to_date(now()) as SnapshotDate from bdl_analytics_sandbox.ds_churn_postpaiduniverse_new group by 1,2,3) b on SUBSTRING(a1.login,1,11) = b.msisdn
                        LEFT JOIN bdl_dm.dimproduct p1 ON a1.contract_name=p1.productname AND p1.isactive=1
                        where stcservicetype <> 'OtherContract - EarlyTerm'     
        union   
                        SELECT productid, stcservicetype ,producttype ,  SUBSTRING(a1.msisdn,1,11) AS msisdn, subscriberid ,
                        a1.contract_startdt AS start_date, a1.contract_enddt AS end_date, product_name, 'Expiry' source 
                        from bdl_raw.brm_contractexpiry a1
                        inner join (select subscriberid, msisdn, to_date(now()) as SnapshotDate from bdl_analytics_sandbox.ds_churn_postpaiduniverse_new group by 1,2,3) b on SUBSTRING(a1.msisdn,1,11) = b.msisdn
                        LEFT JOIN bdl_dm.dimproduct p1 ON a1.product_name=p1.productname AND p1.isactive=1 
                        where stcservicetype <> 'OtherContract - EarlyTerm' ) T
                        ) a where rank = 1              
                        ) b on a.subscriberid = b.subscriberid
        left join
        --->  last device purchased        
        -- later on get number of devices purchased 
        (SELECT  subscriberid , MAX(CASE WHEN rank = 1 THEN desc_text END) last_device_purchased FROM 
         ( SELECT serial_num   msisdn , serv_acct_id subscriberid , desc_text , a.type_cd , x_stc_serial_num , x_stc_mrc_total , producttype ,  stcservicetype ,
           ROW_NUMBER() OVER(PARTITION BY serv_acct_id ORDER BY a.last_upd DESC) AS rank FROM bdl_raw.crm_s_asset a , bdl_dm.dimproduct b , 
           (select subscriberid, msisdn, to_date(now()) as SnapshotDate from bdl_analytics_sandbox.ds_churn_postpaiduniverse_new --bdl_ds.ds_churn_factuniversepostpaid where SnapshotDate=from_utc_timestamp(now() ,'Asia/Bahrain') between -1 and 0  --to_date(cast(from_unixtime(unix_timestamp(now() - interval dayofmonth(date_add(now(),0)) days), 'yyyyMMdd') as int)) 
           group by 1,2,3) c
          WHERE a.serv_acct_id = c.subscriberid   AND b.producttype = 'Equipment'   AND b.productid = a.prod_id  ) a group by subscriberid ) c on a.subscriberid = c.subscriberid      
        ----> failed payments
        left join
        ( select a.subscriberid, count(distinct paymentuniquenumber) as ttl_freq, max(sqldate) as latest_failed_date
        FROM bdl_dm.factmacallapayment a 
        inner join (select subscriberid, msisdn, to_date(now()) as SnapshotDate from bdl_analytics_sandbox.ds_churn_postpaiduniverse_new 
        --bdl_ds.ds_churn_factuniversepostpaid where SnapshotDate=from_utc_timestamp(now() ,'Asia/Bahrain') between -1 and 0  
        --to_date(cast(from_unixtime(unix_timestamp(now() - interval dayofmonth(date_add(now(),0)) days), 'yyyyMMdd') as int)) 
        group by 1,2,3) b
        on a.subscriberid = b.subscriberid
        left outer join bdl_dm.dimpaymentmethod c on a.paymentmethodid = c.paymentmethodid
        inner join bdl_dm.dimtime tm on a.dateid=tm.dateid
        where datediff(from_utc_timestamp(sqldate ,'Asia/Bahrain') , b.SnapshotDate) between -90 and 0 and --finalstatus <> 'Confirmation Success'
        paymentstatusid <> 4
       group by 1
         )
        e on  a.subscriberid = e.subscriberid
