SET SEARCH_PATH = 'my_schema';

CREATE OR REPLACE FUNCTION xirr(debug_log boolean DEFAULT false)
    RETURNS numeric
    LANGUAGE 'plpgsql'

AS $BODY$
DECLARE
	-- XIRR values starting at a wide interval and converge towards the true value
	rmin	DECIMAL(12, 8) ;
    	rmax	DECIMAL(12, 8) ;
    	rmid	DECIMAL(12, 8) ;
	rprev   DECIMAL(12, 8) ;

	-- XNPV values as we converge towards the zero. These can go real big at the outer bounds. Thus keep sufficient size.
    	fmin	DECIMAL(60, 8) ;
    	fmax 	DECIMAL(60, 8) ;
	fmid	DECIMAL(60, 8) ;

	iterator 		INT = 0;
	t0 		 	date;
	investment_count 	INT =0;
	income_count 		INT = 0;

BEGIN

	-- Check for error conditions 
	SELECT COUNT(*) INTO investment_count
	FROM xirr_input
	WHERE transaction_value < 0;
	
	IF investment_count = 0 THEN
		RETURN -101;
	END IF;
	
	SELECT COUNT(*)  INTO income_count
	FROM xirr_input
	WHERE transaction_value > 0;

	IF income_count = 0 THEN
		RETURN -102;
	END IF;

	rmin = -0.99; 	-- can not go below -1 i.e. -100% profit XIRR formula fails at that value
	rmax = 5;   	-- 500% profit
	rprev = -1;  -- Random but outside the boundary value for the previous r value
	
	-- pre-compute the date-diffs
	select min(transaction_date) into t0 from xirr_input;
	update xirr_input set delta_years = (transaction_date - t0)/365.0;
	
	--Compute Vi values for the extreme outer range values
	SELECT 	SUM(transaction_value / (1 + rmin)^delta_years),
		SUM(transaction_value / (1 + rmax)^delta_years) INTO fmin, fmax
	FROM xirr_input;

	-- Signs of Fmin and Fmax are same. can not converge in this scenario
	If (fmin > 0 AND fmax > 0) OR (fmin <0 AND fmax < 0) Then
		IF debug_log THEN
			RAISE NOTICE 'XIRR Value is outside the limits given.';
		END IF;
		Return -103;
	End If;

	WHILE iterator < 101 LOOP

		rmid = (rmin + rmax)/2;
		
		IF debug_log THEN
			RAISE NOTICE 'iteration# = % rmin = % rmid = % rmax = % rprev = % fmin = % fmid = % fmax = %', iterator, rmin, rmid, rmax, rprev, fmin, fmid, fmax;
		END IF;
		
		--Compute Vi for the new rmid value
		SELECT SUM(transaction_value / (1 + rmid)^delta_years) INTO fmid
		FROM xirr_input;

		If (ABS(fmid) < 0.0000001) OR (ABS(rmid-rprev) < 0.000001 ) THEN -- we have reached the required precision
			
			IF debug_log THEN
				RAISE NOTICE 'Found it ... XIRR = %  at XNPV = %,  ABS(rmid-rprev)= %', rmid, fmid, ABS(rmid-rprev);
			END IF;
			
			Return rmid;
		End If;

		iterator = iterator + 1;

		-- Signs of Fmin and Fmid are same	
		If (fmin > 0 AND fmid > 0) OR (fmin < 0 AND fmid < 0) Then
			rmin = rmid;
			fmin = fmid;
		Else -- Signs of fmax and fmid are same
			rmax = rmid;
			fmax = fmid;
		ENd IF;
		
		rprev = rmid;
		
	END LOOP;

	IF debug_log THEN
		RAISE NOTICE 'Could not converge after 100 iterations. Last XIRRn = %', rmid;
	END IF;

	Return -100; -- No convergence even after 100 iterations

EXCEPTION 
	WHEN OTHERS THEN
		RETURN -105; -- Numerical out of bound error occured
END;
$BODY$;

