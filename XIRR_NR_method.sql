
CREATE OR REPLACE FUNCTION xirr_nr(
	initial_guess numeric DEFAULT 0.1,
	max_iterations integer DEFAULT 100,
	debug_log boolean DEFAULT false)
    RETURNS numeric
    LANGUAGE 'plpgsql'
AS $BODY$
DECLARE
	tolerance 	 DECIMAL(1,9) = 0.000000001;
	iterator 	 INT = 0;
	investment_count INT = 0;
	income_count	 INT = 0;	
	total_investment DECIMAL(40,8);
	total_income	 DECIMAL(40,8);
	f_xirr		 DECIMAL(40,8);
	f_xirr_df	 DECIMAL(40,8);
	xirr_n		 DECIMAL(20,8);
	xirr_n1		 DECIMAL(20,8);

BEGIN

	-- Check for error conditions 
	SELECT COUNT(*), SUM(transaction_value) INTO income_count, total_income
	FROM  xirr_input
	WHERE transaction_value > 0;

	IF income_count = 0 THEN
		RETURN -102;
	END IF;

	SELECT COUNT(*), SUM(-transaction_value) INTO investment_count, total_investment
	FROM  xirr_input
	WHERE transaction_value < 0;
	
	IF investment_count = 0 THEN
		RETURN -103;
	END IF;

	-- pre-compute the date-diffs in years and fractions there of
	UPDATE xirr_input 
	SET delta_years = ( (SELECT MIN(transaction_date) FROM xirr_input) - transaction_date ) / 365.0;  -- Number of years lapsed (with -ve sign)
	
	-- Initial guess
	xirr_n = initial_guess;
	
	WHILE iterator < max_iterations LOOP
		
		IF debug_log THEN
			RAISE NOTICE 'XIRRn = %,  fx = %, dfx = %  ', xirr_n, f_xirr, f_xirr_df;
		END IF;
		
		-- Compute the root and the derivative function values
		BEGIN
			SELECT 	SUM(transaction_value * (1 + xirr_n)^delta_years) ,  -- XIRR root function f(x)
					SUM(delta_years * transaction_value * (1 + xirr_n)^(delta_years - 1.0)) -- derivative of XIRR root function f'(x)
					INTO f_xirr, f_xirr_df
			FROM xirr_input;
		EXCEPTION -- Above computation may hit numerical limits and cause run-time errors
			WHEN OTHERS THEN
				RETURN -101; -- Errors like Numerical out of boud, division by zero etc. These occur when your xirr value is going out of bounds
		END;
		
		--Newton-Raphson method says Xn+1 = Xn - f(x) / f'(x)
		xirr_n1 = xirr_n - (f_xirr / f_xirr_df);  
		
		If ABS(xirr_n1 - xirr_n) < tolerance THEN -- we have reached the required precision
			IF debug_log THEN
				RAISE NOTICE 'XIRRn = %,  fx = %, dfx = %  ', xirr_n1, f_xirr, f_xirr_df;
			END IF;
			Return xirr_n1;
		End If;
		
		-- Prepare the values for the next iteration
		iterator = iterator + 1;
		xirr_n = xirr_n1; -- This is standard Newton-Raphson menthod
		
		-- Below steps in not strictly necessary but is improvisation which may help at-times.
		IF xirr_n1 > 100000 THEN -- 10,000,000% return is not a practical XIRR you encounter anyway and you are unlikely to converge
			xirr_n = -0.99; -- reset the guess to the lowest possible value of -99% and see what happens
		END IF;

	END LOOP;

	IF debug_log THEN
		RAISE NOTICE 'No convergence even after % iterations ', iterator;
	END IF;

	Return -100; -- No convergence even after defined number of iterations

END;
$BODY$;

