CREATE OR REPLACE PACKAGE BODY CARSUSR.FS_INTERFACE_PKG AS
    PROCEDURE LOG_BATCH_ERROR(
                p_errorDetail   CARS_ERROR_LOG.ERROR_DETAIL%TYPE,
                p_errorCode     CARS_ERROR_LOG.ERROR_CODE%TYPE,
                p_errorMessage  CARS_ERROR_LOG.ERROR_MESSAGE%TYPE
                ) AS
    BEGIN       
        LOG_CARS_ERROR(1, 'ERROR', p_errorDetail, p_errorCode, p_errorMessage, c_CARS_DB);

    END LOG_BATCH_ERROR;
    
    PROCEDURE LOG_CARS_ERROR(
                p_errorLevel    CARS_ERROR_LOG.ERROR_LEVEL%TYPE,
                p_severity      CARS_ERROR_LOG.SEVERITY%TYPE,
                p_errorDetail   CARS_ERROR_LOG.ERROR_DETAIL%TYPE,
                p_errorCode     CARS_ERROR_LOG.ERROR_CODE%TYPE,
                p_errorMessage  CARS_ERROR_LOG.ERROR_MESSAGE%TYPE,
                p_dataSource    CARS_ERROR_LOG.DATA_SOURCE_CODE%TYPE
                ) IS  PRAGMA AUTONOMOUS_TRANSACTION;
        -- Added procedure to log error in data processing

        v_error_code             NUMBER;
        v_error_msg              VARCHAR2(100);

    BEGIN

        --Check if all input parameters passed have value
        IF  (p_errorDetail is not null) and (p_severity is not null) and 
            (p_errorLevel is not null)THEN

            INSERT INTO CARS_ERROR_LOG 
            ( 
                ERROR_LOG_ID,
                ERROR_LEVEL,
                SEVERITY,
                ERROR_DETAIL,
                ERROR_CODE,
                ERROR_MESSAGE,
                ECID,
                DATA_SOURCE_CODE,
                CREATED_BY,
                CREATED_DATE,
                MODIFIED_BY,
                MODIFIED_DATE
            )
            VALUES
            (
                ERROR_LOG_ID_SEQ.NEXTVAL, 
                p_errorLevel, 
                p_severity, 
                p_errorDetail,
                p_errorCode,
                p_errorMessage,
                0, 
                NVL(p_dataSource,c_CARS_DB), 
                c_USER, 
                SYSDATE,
                NULL,
                NULL
            );    
            
            COMMIT;  
             
         END IF;   

    EXCEPTION
        WHEN OTHERS THEN
            v_error_code := SQLCODE;
            v_error_msg := SUBSTR(SQLERRM, 1 , 100);
            DBMS_OUTPUT.PUT_LINE('The Error could not be logged '|| v_error_code || ': ' || v_error_msg);

    END LOG_CARS_ERROR;
    
-- INFAR001 FUNCTIONS
    FUNCTION FUNC_GET_FS_DEPOSIT(
        programUnit IN VARCHAR2, 
        eventDate   IN DATE, 
        depositSlip IN VARCHAR2, 
        depositDate IN DATE, 
        receiptType IN VARCHAR2)
    RETURN VARCHAR2 IS
    -- Provide programUnit, eventDate, depositSlip, receiptType for Check/EDF
    -- Provide depositDate, depositSlip, receiptType for every other payment
    /******************************************************************************
    NAME:       FUNC_GET_FS_DEPOSIT
    REVISIONS:
    Ver        Date        Author           Description
    ---------  ----------  ---------------  ------------------------------------
    1.0        2/16/2018   Terence Pan      1. Created this function.                                    
    ******************************************************************************/

    c_PAD_00    CONSTANT    VARCHAR2(2) := '00';
    c_PAD_01    CONSTANT    VARCHAR2(2) := '01';
    c_PAD_02    CONSTANT    VARCHAR2(2) := '02';
    c_PAD_03    CONSTANT    VARCHAR2(2) := '03';
        
    varDepositPrefix        VARCHAR2(2);
    varFsDepositNumber      VARCHAR2(10);
    varLast4DepositSlip     VARCHAR(4);
    varLast4DepositSlipLpad VARCHAR2(6);
    varDate                 VARCHAR2(6);
    varPos                  NUMBER;
    varCurrentDoc           VARCHAR2(10);
    varDepositSlipNumber    VARCHAR2(10);
    varMessage              VARCHAR2(200);    

    
    BEGIN
        varFsDepositNumber := NULL;
        
        IF receiptType in('CHECK', 'MONEY_ORDER', 'CASH', 'EDF') THEN

            IF ((programUnit IS NOT NULL ) AND 
                (depositSlip IS NOT NULL ) AND 
                (receiptType IS NOT NULL )) THEN 
                
                varDepositPrefix := NULL;
            
                --get deposit prefix from program unit
                CASE
                    WHEN programUnit = c_PU_CALOSHA THEN
                        varDepositPrefix := c_PAD_01;

                    WHEN programUnit IN (c_PU_ART, c_PU_EV) THEN
                        varDepositPrefix := c_PAD_02;

                    WHEN programUnit = c_PU_PV THEN
                        varDepositPrefix := c_PAD_03;                

                    ELSE 
                        varDepositPrefix := NULL; --raise_application_error(-20101, 'Invalid program unit: ' || programUnit);
                        varMessage       := 'FUNC_GET_FS_DEPOSIT: Invalid input parameter. Program Unit '||programUnit||' does not have a deposit prefix mapping value';
                        DBMS_OUTPUT.PUT_LINE(varMessage);
                        
                        RETURN NULL;
                END CASE;
            
                --convert event date to string and get last 4 deposit slip number
                varDate                 := TO_CHAR(eventDate, 'MMDDYY');
                varPos                  := LENGTH(depositSlip) - 4;
                varLast4DepositSlip     := SUBSTR(depositSlip, varPos + 1, 4);
                varLast4DepositSlipLpad := LPAD(varLast4DepositSlip, 6, 0);
            
                --get the prefix and postfix    
                varFsDepositNumber := '2108' || varLast4DepositSlipLpad;
                
            END IF;

        --Deposit Number for every other payment type
        ELSE 
            varCurrentDoc           := NULL;
            varDepositSlipNumber    := depositSlip;
            
            IF (varDepositSlipNumber IS NOT NULL) THEN
                varDepositSlipNumber := TRIM(varDepositSlipNumber);
            END IF;
            
            IF ((varDepositSlipNumber IS NOT NULL   OR LENGTH(varDepositSlipNumber) > 0) AND
               (receiptType IS NOT NULL             OR LENGTH(receiptType) > 0)) THEN
             
               --convert event date to string and get last 4 deposit slip number
                varDate                 := TO_CHAR(depositDate, 'YYMMDD');
                varPos                  := LENGTH(varDepositSlipNumber) - 4;
                varLast4DepositSlip     := SUBSTR(varDepositSlipNumber, varPos + 1, 4);
                varLast4DepositSlipLpad := LPAD(varLast4DepositSlip, 6, 0);
            
                --get the prefix and postfix
                CASE 
            
                    WHEN receiptType IN ('VISA_MASTER_CREDIT_CARD',
                                        'AMEX_CREDIT_CARD',
                                        'DISCOVER_CREDIT_CARD', 
                                        'CREDIT_CARD_REJECT')                   THEN    varCurrentDoc := 'ZB' || varDate || c_PAD_00;
                    WHEN receiptType IN ('JPMC_LOCK_BOX')                       THEN    varCurrentDoc := 'LX' || varDate || c_PAD_00;               
                    WHEN receiptType IN ('USB_LOCK_BOX')                        THEN    varCurrentDoc := 'BX' || varDate || c_PAD_00;
                    WHEN receiptType IN ('EFT', 'EFT_REJECT')                   THEN    varCurrentDoc := 'ZB' || varDate || c_PAD_01;
                    WHEN receiptType IN ('ACCOUNT_TRANSFER', 'EDD_REJECT',
                                        'EDD_UNAPPLIED_REJECT')                 THEN    varCurrentDoc := 'AT' || varLast4DepositSlipLpad || c_PAD_02;
                    WHEN receiptType IN ('CHECK', 'MONEY_ORDER', 'CASH', 'EDF') THEN    varCurrentDoc := 'DS' || varLast4DepositSlipLpad || c_PAD_02;
                    ELSE                                                                varCurrentDoc := NULL; 
                        varMessage    := 'FUNC_GET_FS_DEPOSIT: Invalid input parameter. Receipt Type '||receiptType||' could not generate a current document value';
                        DBMS_OUTPUT.PUT_LINE(varMessage);

                        RETURN NULL;
                END CASE;
            
            END IF;
            
            varFsDepositNumber := varCurrentDoc;   
        
        END IF;
        
        RETURN varFsDepositNumber;
    
    EXCEPTION
        WHEN OTHERS THEN
                -- Consider logging the error and then re-raise
            varFsDepositNumber  := NULL;
            varMessage          := 'FUNC_GET_FS_DEPOSIT: '||' programUnit '||programUnit||' eventDate '||eventDate||' receiptType '||receiptType
                                                          ||' depositSlip '||depositSlip||' depositDate '||depositDate||' '||SQLERRM;
            DBMS_OUTPUT.PUT_LINE(varMessage);
        
           LOG_CARS_ERROR(
                p_errorLevel    => '3',
                p_severity      => c_HIGH_SEVERITY,
                p_errorDetail   => 'FISCAL FUNC_GET_FS_DEPOSIT function could not return deposit number',
                p_errorCode     => '5000',
                p_errorMessage  => varMessage,
                p_dataSource    => c_CARS_DB
              );
            
            RETURN NULL;
    
    END FUNC_GET_FS_DEPOSIT;
    
    FUNCTION FUNC_GET_BILLED_PP_SW(programUnitCode IN VARCHAR2) RETURN VARCHAR2 IS
        
    /******************************************************************************
    NAME:       FUNC_GET_BILLED_PP_SW
    
    REVISIONS:
    Ver        Date        Author           Description
    ---------  ----------  ---------------  ------------------------------------
    1.0        9/11/2018   Terence Pan      1. Created this function.                                    
    ******************************************************************************/
        ppSw INFAR001_OUTBOUND.PP_SW%TYPE;    

    BEGIN
        /*
        Always N for CAlOSHA/DLSE, Y for Others
        */

        CASE 
            WHEN programUnitCode IN ('CALOSHA','DLSE')  
				THEN ppSw := 'N';
            ELSE  
				ppSw := 'Y';

        END CASE;
                
        RETURN ppSw;

    EXCEPTION
        WHEN OTHERS THEN
            -- Consider logging the error and then re-raise
            -- Consider logging the error and then re-raise
            -- Removed RAISE, added return null.
            DBMS_OUTPUT.PUT_LINE('FUNC_GET_BILLED_PP_SW : '||SQLERRM);
            
           LOG_CARS_ERROR(
                p_errorLevel    => '3',
                p_severity      => c_HIGH_SEVERITY,
                p_errorDetail   => 'FISCAL FUNC_GET_BILLED_PP_SW function could not return payment method',
                p_errorCode     => '5000',
                p_errorMessage  => 'FUNC_GET_BILLED_PP_SW : '||SQLERRM,
                p_dataSource    => c_CARS_DB
              );
    
            RETURN NULL;
    
    END FUNC_GET_BILLED_PP_SW;
    
    FUNCTION FUNC_GET_FS_PAYMENT_METHOD(receiptType IN VARCHAR2) RETURN VARCHAR2 IS
        
    /******************************************************************************
    NAME:       FUNC_GET_FS_PAYMENT_METHOD
    
    REVISIONS:
    Ver        Date        Author           Description
    ---------  ----------  ---------------  ------------------------------------
    1.0        1/26/2018   Terence Pan      1. Created this function.                                    
    ******************************************************************************/
        fsPaymentMethod INFAR001_OUTBOUND.ZZ_PAYMENT_METHOD%TYPE;    

    BEGIN
        /*
        CC     Credit Card
        CCK    Cashier's Check
        CHK    Check
        CSH    Cash
        DC     Debit Card
        EFT    EFT
        FTR    Funds Transfer
        MO     Money Order
        OFF    Offset
        WIR    Wire / ACH
        */

        CASE 
            WHEN receiptType IN ('CHECK','EDF', 'JPMC_LOCK_BOX', 'USB_LOCK_BOX')  THEN                                  fsPaymentMethod := 'CHK';
            WHEN receiptType IN ('VISA_MASTER_CREDIT_CARD', 'AMEX_CREDIT_CARD', 'DISCOVER_CREDIT_CARD')  THEN     fsPaymentMethod := 'CC';
            WHEN receiptType IN ('MONEY_ORDER')  THEN       fsPaymentMethod := 'MO';
            WHEN receiptType IN ('CASH')  THEN              fsPaymentMethod := 'CSH';
            WHEN receiptType IN ('EFT')  THEN               fsPaymentMethod := 'EFT';
            WHEN receiptType IN ('ACCOUNT_TRANSFER') THEN   fsPaymentMethod := 'FTR';

        END CASE;
                
        RETURN fsPaymentMethod;

    EXCEPTION
        WHEN OTHERS THEN
            -- Consider logging the error and then re-raise
            -- Consider logging the error and then re-raise
            -- Removed RAISE, added return null.
            DBMS_OUTPUT.PUT_LINE('FUNC_GET_FS_PAYMENT_METHOD : '||SQLERRM);
            
           LOG_CARS_ERROR(
                p_errorLevel    => '3',
                p_severity      => c_HIGH_SEVERITY,
                p_errorDetail   => 'FISCAL FUNC_GET_FS_PAYMENT_METHOD function could not return payment method',
                p_errorCode     => '5000',
                p_errorMessage  => 'FUNC_GET_FS_PAYMENT_METHOD : '||SQLERRM,
                p_dataSource    => c_CARS_DB
              );
    
            RETURN NULL;
    
    END FUNC_GET_FS_PAYMENT_METHOD;
    
    FUNCTION FUNC_GET_FS_DEPOSIT_PFX(programUnitCode IN VARCHAR2) RETURN VARCHAR2 IS
    /******************************************************************************
    NAME:       FUNC_GET_FS_DEPOSIT_PFX
    
    REVISIONS:
    Ver        Date        Author           Description
    ---------  ----------  ---------------  ------------------------------------
    1.0        2/19/2018   Terence Pan      1. Created this function.                                    
    ******************************************************************************/
        
        depositPfx INFAR001_OUTBOUND.ZZ_PAYMENT_METHOD%TYPE;
            
    BEGIN
        CASE programUnitCode
        WHEN 'CALOSHA'  THEN depositPfx := 'OSH';
        WHEN 'EV'       THEN depositPfx := 'EV'; 
        WHEN 'ART'      THEN depositPfx := 'ART'; 
        WHEN 'PV'       THEN depositPfx := 'PV'; 
        WHEN 'OSIP'     THEN depositPfx := 'SIP'; 
        WHEN 'DLSE'     THEN depositPfx := 'DLSE'; 
        WHEN 'DWC'      THEN depositPfx := 'DWC'; 
        WHEN 'PSM'      THEN depositPfx := 'PSM'; 
        END CASE;
               
        RETURN depositPfx;

    EXCEPTION
        WHEN OTHERS THEN
            -- Consider logging the error and then re-raise
            -- Removed RAISE, added return null.
            DBMS_OUTPUT.PUT_LINE('FUNC_GET_FS_DEPOSIT_PFX : '||SQLERRM);
            
           LOG_CARS_ERROR(
                p_errorLevel    => '3',
                p_severity      => c_HIGH_SEVERITY,
                p_errorDetail   => 'FISCAL FUNC_GET_FS_DEPOSIT_PFX function could not find deposit prefix',
                p_errorCode     => '5000',
                p_errorMessage  => 'FUNC_GET_FS_DEPOSIT_PFX : '||SQLERRM,
                p_dataSource    => c_CARS_DB
                );
                
            RETURN NULL;
    
    END FUNC_GET_FS_DEPOSIT_PFX;
    
    FUNCTION FUNC_GET_FS_DEPOSIT_TYPE( receiptType IN VARCHAR2) RETURN VARCHAR2 IS
    /******************************************************************************
    NAME:       FUNC_GET_FS_DEPOSIT_TYPE
    REVISIONS:
    Ver        Date        Author           Description
    ---------  ----------  ---------------  ------------------------------------
    1.0        2/21/2018   Terence Pan      1. Created this function.                                    
    ******************************************************************************/        

        fsDepositType INFAR001_OUTBOUND.DEPOSIT_TYPE%TYPE;
    
    BEGIN
        /*
        CC    Credit Card
        CCK   Cashier's Check
        CHK   Check
        CSH   Cash
        DC    Debit Card
        EFT   EFT
        FTR   Funds Transfer
        MO    Money Order
        OFF   Offset
        WIR   Wire / ACH
        */

        CASE 
            WHEN receiptType IN ('EFT','VISA_MASTER_CREDIT_CARD', 'AMEX_CREDIT_CARD', 
                                'DISCOVER_CREDIT_CARD', 'JPMC_LOCK_BOX', 'USB_LOCK_BOX',
                                'EDF' )  THEN  
                                                                                fsDepositType := 'R';
            --WHEN receiptType IN ('ACCOUNT_TRANSFER') THEN                       fsDepositType := 'T';
            WHEN receiptType IN ('CHECK', 'MONEY_ORDER', 'CASH') THEN     fsDepositType := 'R';

        END CASE;

        RETURN fsDepositType;
    
    EXCEPTION
        WHEN OTHERS THEN
            -- Consider logging the error and then re-raise
            -- Removed RAISE, added return null.
            DBMS_OUTPUT.PUT_LINE('FUNC_GET_FS_DEPOSIT_TYPE : '||SQLERRM);
            
           LOG_CARS_ERROR(
                p_errorLevel    => '3',
                p_severity      => c_HIGH_SEVERITY,
                p_errorDetail   => 'FISCAL FUNC_GET_FS_DEPOSIT_TYPE function could not return deposit type',
                p_errorCode     => '5000',
                p_errorMessage  => 'FUNC_GET_FS_DEPOSIT_TYPE : '||SQLERRM,
                p_dataSource    => c_CARS_DB
              );
    
            RETURN NULL;
    
    END FUNC_GET_FS_DEPOSIT_TYPE;
    
    -- INFAR006 FUNCTIONS
    FUNCTION GET_FS_ADDRESS_ID(varReferenceDoc VARCHAR2) RETURN VARCHAR2 IS
    
        varAddressId    PARTICIPANT_ROLE.CUST_ID%TYPE;
        varMsg          VARCHAR2(500);
    BEGIN
        varAddressId    := NULL;
        varMsg          := NULL;
    
        -- 5/24/2018, Vinay Patil: Get the Address Sequence Number based on AR setup event.
        SELECT  ADDRESS.FS_SEQUENCE_NUMBER 
        INTO    varAddressId
        FROM    EVENT
            INNER JOIN PARTICIPANT_ROLE ON PARTICIPANT_ROLE.EVENT_ID = EVENT.EVENT_ID
            INNER JOIN ADDRESS          ON PARTICIPANT_ROLE.PARTY_ID = ADDRESS.PARTY_ID
            INNER JOIN EVENT_TYPE       ON EVENT.EVENT_TYPE_ID       = EVENT_TYPE.EVENT_TYPE_ID
        WHERE EVENT_TYPE.EVENT_TYPE_CODE IN (c_EVENT_010, c_EVENT_015)
          AND EVENT.CURRENT_DOCUMENT  = varReferenceDoc
          AND EVENT.AR_ROOT_DOCUMENT  = varReferenceDoc;

        -- If AR Setup event related address exists however the FS Address Sequence number is null or blank
        IF (varAddressId IS NULL) THEN
        
            varMsg := 'Invoice Number: ' || varReferenceDoc || ' does not have Fiscal Address Sequence Number on the AR Setup event transaction.';

            LOG_CARS_ERROR(
                    p_errorLevel    => '3',
                    p_severity      => c_HIGH_SEVERITY,
                    p_errorDetail   => 'Missing FS Sequence Number Information',
                    p_errorCode     => '5000',
                    p_errorMessage  => varMsg,
                    p_dataSource    => c_CARS_DB
	                );  
                    
           DBMS_OUTPUT.PUT_LINE('GET_FS_ADDRESS_ID function: '|| varMsg );        
        END IF;
        
        RETURN varAddressId;
        
    EXCEPTION
        WHEN OTHERS THEN
            -- Consider logging the error and then re-raise
            -- Removed RAISE, added return null.
            DBMS_OUTPUT.PUT_LINE('GET_FS_ADDRESS_ID : '||SQLERRM);
            
           LOG_CARS_ERROR(
                p_errorLevel    => '3',
                p_severity      => c_HIGH_SEVERITY,
                p_errorDetail   => 'FISCAL GET_FS_ADDRESS_ID function could not return Fiscal Address Sequence Number on the AR Setup event transaction',
                p_errorCode     => '5000',
                p_errorMessage  => 'GET_FS_ADDRESS_ID : '||SQLERRM,
                p_dataSource    => c_CARS_DB
              );
    
            RETURN NULL;
            
    END GET_FS_ADDRESS_ID;

    --  
    --  Gets the Credit Amount
    --/ 
    FUNCTION GET_FS_CREDIT_AMOUNT(varAcctEntryId NUMBER) RETURN VARCHAR2 IS
    
        varCreditAmount VARCHAR2(25);
    
    BEGIN

        SELECT CREDIT.AMOUNT INTO varCreditAmount
        FROM CREDIT
            INNER JOIN ACCOUNTING_ENTRY  ON (ACCOUNTING_ENTRY.ACCTG_ENTRY_ID = CREDIT.ACCTG_ENTRY_ID)
            INNER JOIN CREDIT_RULE       ON (CREDIT_RULE.ACCTG_ENTRY_TYPE_ID = ACCOUNTING_ENTRY.ACCTG_ENTRY_TYPE_ID) 
        WHERE CREDIT_RULE.EFFECTIVE_END_DATE IS NULL
          AND ACCOUNTING_ENTRY.ACCTG_ENTRY_ID = varAcctEntryId;

        RETURN varCreditAmount;
        
    EXCEPTION
        WHEN OTHERS THEN
            -- Consider logging the error and then re-raise
            -- Removed RAISE, added return null.
            DBMS_OUTPUT.PUT_LINE('GET_FS_CREDIT_AMOUNT : '||SQLERRM);
            
           LOG_CARS_ERROR(
                p_errorLevel    => '3',
                p_severity      => c_HIGH_SEVERITY,
                p_errorDetail   => 'FISCAL GET_FS_CREDIT_AMOUNT function could not return credit amount',
                p_errorCode     => '5000',
                p_errorMessage  => 'GET_FS_CREDIT_AMOUNT : '||SQLERRM,
                p_dataSource    => c_CARS_DB
              );
    
            RETURN NULL;

    END GET_FS_CREDIT_AMOUNT;    
    
    --  
    --  Gets the Debit Amt
    -- 
    FUNCTION GET_FS_DEBIT_AMOUNT(varAcctEntryId NUMBER) RETURN VARCHAR2 is
    
       varDebitAmount VARCHAR2(25);
    BEGIN

        SELECT DEBIT.AMOUNT INTO varDebitAmount
        FROM DEBIT
            INNER JOIN ACCOUNTING_ENTRY  ON (ACCOUNTING_ENTRY.ACCTG_ENTRY_ID = DEBIT.ACCTG_ENTRY_ID)
            INNER JOIN DEBIT_RULE        ON (DEBIT_RULE.ACCTG_ENTRY_TYPE_ID  = ACCOUNTING_ENTRY.ACCTG_ENTRY_TYPE_ID)    
        WHERE DEBIT_RULE.EFFECTIVE_END_DATE IS NULL
          AND ACCOUNTING_ENTRY.ACCTG_ENTRY_ID = varAcctEntryId;

        RETURN varDebitAmount;
        
    EXCEPTION
        WHEN OTHERS THEN
            -- Consider logging the error and then re-raise
            -- Removed RAISE, added return null.
            DBMS_OUTPUT.PUT_LINE('GET_FS_DEBIT_AMOUNT : '||SQLERRM);
            
           LOG_CARS_ERROR(
                p_errorLevel    => '3',
                p_severity      => c_HIGH_SEVERITY,
                p_errorDetail   => 'FISCAL GET_FS_DEBIT_AMOUNT function could not return debit amount',
                p_errorCode     => '5000',
                p_errorMessage  => 'GET_FS_DEBIT_AMOUNT : '||SQLERRM,
                p_dataSource    => c_CARS_DB
              );
    
            RETURN NULL;

    END GET_FS_DEBIT_AMOUNT;
    
    -- 
    -- Returns the correct Account based on transaction type
    -- Revenue will return revenue source
    --
    FUNCTION GET_FS_GL_REV_SRC(
        varAcctEntryId      NUMBER, 
        varSystemDefined    VARCHAR2, 
        varFsEntryType      VARCHAR2,
        varTransactionCode  VARCHAR2) RETURN VARCHAR2 IS
        
        varAccount          VARCHAR2(7);
        varArRevenueFlag    VARCHAR2(1) := c_NO;
    BEGIN

        IF varTransactionCode IN ('120', '460', '466') THEN 
        
            varArRevenueFlag := c_YES;
        
        END IF;
        
        IF varFsEntryType = c_DR and varSystemDefined = c_A_LINE THEN
        
                SELECT DEBIT.ACCOUNT_NUMBER INTO varAccount           
                FROM DEBIT
                INNER JOIN ACCOUNTING_ENTRY
                    ON (ACCOUNTING_ENTRY.ACCTG_ENTRY_ID = DEBIT.ACCTG_ENTRY_ID)
                INNER JOIN DEBIT_RULE
                    ON (DEBIT_RULE.ACCTG_ENTRY_TYPE_ID = ACCOUNTING_ENTRY.ACCTG_ENTRY_TYPE_ID)    
                INNER JOIN GL_ACCOUNT
                    ON (GL_ACCOUNT.ACCOUNT_NUMBER = DEBIT_RULE.ACCOUNT_NUMBER)    
                INNER JOIN ACCOUNTING_CODE
                    ON (ACCOUNTING_CODE.ACCOUNTING_CODE_ID = ACCOUNTING_ENTRY.ACCOUNTING_CODE_ID)            
                WHERE ACCOUNTING_ENTRY.ACCTG_ENTRY_ID = varAcctEntryId;   

        ELSIF varFsEntryType = c_DR and varSystemDefined = c_U_LINE and varArRevenueFlag = c_YES THEN

                SELECT ACCOUNTING_CODE.REVENUE_SOURCE_CODE INTO varAccount           
                FROM DEBIT
                INNER JOIN ACCOUNTING_ENTRY
                    ON (ACCOUNTING_ENTRY.ACCTG_ENTRY_ID = DEBIT.ACCTG_ENTRY_ID)
                INNER JOIN DEBIT_RULE
                    ON (DEBIT_RULE.ACCTG_ENTRY_TYPE_ID = ACCOUNTING_ENTRY.ACCTG_ENTRY_TYPE_ID)    
                INNER JOIN GL_ACCOUNT
                    ON (GL_ACCOUNT.ACCOUNT_NUMBER = DEBIT_RULE.ACCOUNT_NUMBER)    
                INNER JOIN ACCOUNTING_CODE
                    ON (ACCOUNTING_CODE.ACCOUNTING_CODE_ID = ACCOUNTING_ENTRY.ACCOUNTING_CODE_ID)            
                WHERE ACCOUNTING_ENTRY.ACCTG_ENTRY_ID = varAcctEntryId;    

        ELSIF varFsEntryType = c_DR and varSystemDefined = c_U_LINE and varArRevenueFlag = c_NO THEN

                SELECT CREDIT.ACCOUNT_NUMBER INTO varAccount              
                FROM CREDIT
                INNER JOIN ACCOUNTING_ENTRY
                    ON (ACCOUNTING_ENTRY.ACCTG_ENTRY_ID = CREDIT.ACCTG_ENTRY_ID)
                INNER JOIN DEBIT_RULE
                    ON (DEBIT_RULE.ACCTG_ENTRY_TYPE_ID = ACCOUNTING_ENTRY.ACCTG_ENTRY_TYPE_ID)    
                INNER JOIN GL_ACCOUNT
                    ON (GL_ACCOUNT.ACCOUNT_NUMBER = DEBIT_RULE.ACCOUNT_NUMBER)    
                INNER JOIN ACCOUNTING_CODE
                    ON (ACCOUNTING_CODE.ACCOUNTING_CODE_ID = ACCOUNTING_ENTRY.ACCOUNTING_CODE_ID)            
                WHERE ACCOUNTING_ENTRY.ACCTG_ENTRY_ID = varAcctEntryId;   

        ELSIF varFsEntryType = c_CR and varSystemDefined = c_A_LINE THEN

                SELECT CREDIT.ACCOUNT_NUMBER INTO varAccount           
                FROM CREDIT
                INNER JOIN ACCOUNTING_ENTRY
                    ON (ACCOUNTING_ENTRY.ACCTG_ENTRY_ID = CREDIT.ACCTG_ENTRY_ID)
                INNER JOIN DEBIT_RULE
                    ON (DEBIT_RULE.ACCTG_ENTRY_TYPE_ID = ACCOUNTING_ENTRY.ACCTG_ENTRY_TYPE_ID)    
                INNER JOIN GL_ACCOUNT
                    ON (GL_ACCOUNT.ACCOUNT_NUMBER = DEBIT_RULE.ACCOUNT_NUMBER)    
                INNER JOIN ACCOUNTING_CODE
                    ON (ACCOUNTING_CODE.ACCOUNTING_CODE_ID = ACCOUNTING_ENTRY.ACCOUNTING_CODE_ID)            
                WHERE ACCOUNTING_ENTRY.ACCTG_ENTRY_ID = varAcctEntryId;   

        ELSIF varFsEntryType = c_CR and varSystemDefined = c_U_LINE and varArRevenueFlag = c_YES THEN

                SELECT ACCOUNTING_CODE.REVENUE_SOURCE_CODE INTO varAccount           
                FROM DEBIT
                INNER JOIN ACCOUNTING_ENTRY
                    ON (ACCOUNTING_ENTRY.ACCTG_ENTRY_ID = DEBIT.ACCTG_ENTRY_ID)
                INNER JOIN DEBIT_RULE
                    ON (DEBIT_RULE.ACCTG_ENTRY_TYPE_ID = ACCOUNTING_ENTRY.ACCTG_ENTRY_TYPE_ID)    
                INNER JOIN GL_ACCOUNT
                    ON (GL_ACCOUNT.ACCOUNT_NUMBER = DEBIT_RULE.ACCOUNT_NUMBER)    
                INNER JOIN ACCOUNTING_CODE
                    ON (ACCOUNTING_CODE.ACCOUNTING_CODE_ID = ACCOUNTING_ENTRY.ACCOUNTING_CODE_ID)            
                WHERE ACCOUNTING_ENTRY.ACCTG_ENTRY_ID = varAcctEntryId;   

        ELSIF varFsEntryType = c_CR and varSystemDefined = c_U_LINE and varArRevenueFlag = c_NO THEN

                SELECT DEBIT.ACCOUNT_NUMBER INTO varAccount              
                FROM DEBIT
                INNER JOIN ACCOUNTING_ENTRY
                    ON (ACCOUNTING_ENTRY.ACCTG_ENTRY_ID = DEBIT.ACCTG_ENTRY_ID)
                INNER JOIN DEBIT_RULE
                    ON (DEBIT_RULE.ACCTG_ENTRY_TYPE_ID = ACCOUNTING_ENTRY.ACCTG_ENTRY_TYPE_ID)    
                INNER JOIN GL_ACCOUNT
                    ON (GL_ACCOUNT.ACCOUNT_NUMBER = DEBIT_RULE.ACCOUNT_NUMBER)    
                INNER JOIN ACCOUNTING_CODE
                    ON (ACCOUNTING_CODE.ACCOUNTING_CODE_ID = ACCOUNTING_ENTRY.ACCOUNTING_CODE_ID)            
                WHERE ACCOUNTING_ENTRY.ACCTG_ENTRY_ID = varAcctEntryId;   
                
        ELSIF varFsEntryType = c_DRYEC and varSystemDefined = c_A_LINE THEN
        
                SELECT DEBIT.ACCOUNT_NUMBER INTO varAccount           
                FROM DEBIT
                INNER JOIN ACCOUNTING_ENTRY
                    ON (ACCOUNTING_ENTRY.ACCTG_ENTRY_ID = DEBIT.ACCTG_ENTRY_ID)
                INNER JOIN DEBIT_RULE
                    ON (DEBIT_RULE.ACCTG_ENTRY_TYPE_ID = ACCOUNTING_ENTRY.ACCTG_ENTRY_TYPE_ID)    
                INNER JOIN GL_ACCOUNT
                    ON (GL_ACCOUNT.ACCOUNT_NUMBER = DEBIT_RULE.ACCOUNT_NUMBER)    
                INNER JOIN ACCOUNTING_CODE
                    ON (ACCOUNTING_CODE.ACCOUNTING_CODE_ID = ACCOUNTING_ENTRY.ACCOUNTING_CODE_ID)            
                WHERE ACCOUNTING_ENTRY.ACCTG_ENTRY_ID = varAcctEntryId;   

        ELSIF varFsEntryType = c_DRYEC and varSystemDefined = c_U_LINE and varArRevenueFlag = c_YES THEN

                SELECT ACCOUNTING_CODE.REVENUE_SOURCE_CODE INTO varAccount           
                FROM DEBIT
                INNER JOIN ACCOUNTING_ENTRY
                    ON (ACCOUNTING_ENTRY.ACCTG_ENTRY_ID = DEBIT.ACCTG_ENTRY_ID)
                INNER JOIN DEBIT_RULE
                    ON (DEBIT_RULE.ACCTG_ENTRY_TYPE_ID = ACCOUNTING_ENTRY.ACCTG_ENTRY_TYPE_ID)    
                INNER JOIN GL_ACCOUNT
                    ON (GL_ACCOUNT.ACCOUNT_NUMBER = DEBIT_RULE.ACCOUNT_NUMBER)    
                INNER JOIN ACCOUNTING_CODE
                    ON (ACCOUNTING_CODE.ACCOUNTING_CODE_ID = ACCOUNTING_ENTRY.ACCOUNTING_CODE_ID)            
                WHERE ACCOUNTING_ENTRY.ACCTG_ENTRY_ID = varAcctEntryId;    

        ELSIF varFsEntryType = c_DRYEC and varSystemDefined = c_U_LINE and varArRevenueFlag = c_NO THEN

                SELECT CREDIT.ACCOUNT_NUMBER INTO varAccount              
                FROM CREDIT
                INNER JOIN ACCOUNTING_ENTRY
                    ON (ACCOUNTING_ENTRY.ACCTG_ENTRY_ID = CREDIT.ACCTG_ENTRY_ID)
                INNER JOIN DEBIT_RULE
                    ON (DEBIT_RULE.ACCTG_ENTRY_TYPE_ID = ACCOUNTING_ENTRY.ACCTG_ENTRY_TYPE_ID)    
                INNER JOIN GL_ACCOUNT
                    ON (GL_ACCOUNT.ACCOUNT_NUMBER = DEBIT_RULE.ACCOUNT_NUMBER)    
                INNER JOIN ACCOUNTING_CODE
                    ON (ACCOUNTING_CODE.ACCOUNTING_CODE_ID = ACCOUNTING_ENTRY.ACCOUNTING_CODE_ID)            
                WHERE ACCOUNTING_ENTRY.ACCTG_ENTRY_ID = varAcctEntryId;   

        ELSIF varFsEntryType = c_CRYEC and varSystemDefined = c_A_LINE THEN

                SELECT CREDIT.ACCOUNT_NUMBER INTO varAccount           
                FROM CREDIT
                INNER JOIN ACCOUNTING_ENTRY
                    ON (ACCOUNTING_ENTRY.ACCTG_ENTRY_ID = CREDIT.ACCTG_ENTRY_ID)
                INNER JOIN DEBIT_RULE
                    ON (DEBIT_RULE.ACCTG_ENTRY_TYPE_ID = ACCOUNTING_ENTRY.ACCTG_ENTRY_TYPE_ID)    
                INNER JOIN GL_ACCOUNT
                    ON (GL_ACCOUNT.ACCOUNT_NUMBER = DEBIT_RULE.ACCOUNT_NUMBER)    
                INNER JOIN ACCOUNTING_CODE
                    ON (ACCOUNTING_CODE.ACCOUNTING_CODE_ID = ACCOUNTING_ENTRY.ACCOUNTING_CODE_ID)            
                WHERE ACCOUNTING_ENTRY.ACCTG_ENTRY_ID = varAcctEntryId;   

        ELSIF varFsEntryType = c_CRYEC and varSystemDefined = c_U_LINE and varArRevenueFlag = c_YES THEN

                SELECT ACCOUNTING_CODE.REVENUE_SOURCE_CODE INTO varAccount           
                FROM DEBIT
                INNER JOIN ACCOUNTING_ENTRY
                    ON (ACCOUNTING_ENTRY.ACCTG_ENTRY_ID = DEBIT.ACCTG_ENTRY_ID)
                INNER JOIN DEBIT_RULE
                    ON (DEBIT_RULE.ACCTG_ENTRY_TYPE_ID = ACCOUNTING_ENTRY.ACCTG_ENTRY_TYPE_ID)    
                INNER JOIN GL_ACCOUNT
                    ON (GL_ACCOUNT.ACCOUNT_NUMBER = DEBIT_RULE.ACCOUNT_NUMBER)    
                INNER JOIN ACCOUNTING_CODE
                    ON (ACCOUNTING_CODE.ACCOUNTING_CODE_ID = ACCOUNTING_ENTRY.ACCOUNTING_CODE_ID)            
                WHERE ACCOUNTING_ENTRY.ACCTG_ENTRY_ID = varAcctEntryId;   

        ELSIF varFsEntryType = c_CRYEC and varSystemDefined = c_U_LINE and varArRevenueFlag = c_NO THEN

                SELECT DEBIT.ACCOUNT_NUMBER INTO varAccount              
                FROM DEBIT
                INNER JOIN ACCOUNTING_ENTRY
                    ON (ACCOUNTING_ENTRY.ACCTG_ENTRY_ID = DEBIT.ACCTG_ENTRY_ID)
                INNER JOIN DEBIT_RULE
                    ON (DEBIT_RULE.ACCTG_ENTRY_TYPE_ID = ACCOUNTING_ENTRY.ACCTG_ENTRY_TYPE_ID)    
                INNER JOIN GL_ACCOUNT
                    ON (GL_ACCOUNT.ACCOUNT_NUMBER = DEBIT_RULE.ACCOUNT_NUMBER)    
                INNER JOIN ACCOUNTING_CODE
                    ON (ACCOUNTING_CODE.ACCOUNTING_CODE_ID = ACCOUNTING_ENTRY.ACCOUNTING_CODE_ID)            
                WHERE ACCOUNTING_ENTRY.ACCTG_ENTRY_ID = varAcctEntryId; 

        ELSIF varFsEntryType = c_WO and varSystemDefined = c_A_LINE THEN

                SELECT CREDIT.ACCOUNT_NUMBER INTO varAccount           
                FROM CREDIT
                INNER JOIN ACCOUNTING_ENTRY
                    ON (ACCOUNTING_ENTRY.ACCTG_ENTRY_ID = CREDIT.ACCTG_ENTRY_ID)
                INNER JOIN DEBIT_RULE
                    ON (DEBIT_RULE.ACCTG_ENTRY_TYPE_ID = ACCOUNTING_ENTRY.ACCTG_ENTRY_TYPE_ID)    
                INNER JOIN GL_ACCOUNT
                    ON (GL_ACCOUNT.ACCOUNT_NUMBER = DEBIT_RULE.ACCOUNT_NUMBER)    
                INNER JOIN ACCOUNTING_CODE
                    ON (ACCOUNTING_CODE.ACCOUNTING_CODE_ID = ACCOUNTING_ENTRY.ACCOUNTING_CODE_ID)            
                WHERE ACCOUNTING_ENTRY.ACCTG_ENTRY_ID = varAcctEntryId;   

        ELSIF varFsEntryType = c_WO and varSystemDefined = c_U_LINE and varArRevenueFlag = c_YES THEN

                SELECT ACCOUNTING_CODE.REVENUE_SOURCE_CODE INTO varAccount           
                FROM DEBIT
                INNER JOIN ACCOUNTING_ENTRY
                    ON (ACCOUNTING_ENTRY.ACCTG_ENTRY_ID = DEBIT.ACCTG_ENTRY_ID)
                INNER JOIN DEBIT_RULE
                    ON (DEBIT_RULE.ACCTG_ENTRY_TYPE_ID = ACCOUNTING_ENTRY.ACCTG_ENTRY_TYPE_ID)    
                INNER JOIN GL_ACCOUNT
                    ON (GL_ACCOUNT.ACCOUNT_NUMBER = DEBIT_RULE.ACCOUNT_NUMBER)    
                INNER JOIN ACCOUNTING_CODE
                    ON (ACCOUNTING_CODE.ACCOUNTING_CODE_ID = ACCOUNTING_ENTRY.ACCOUNTING_CODE_ID)            
                WHERE ACCOUNTING_ENTRY.ACCTG_ENTRY_ID = varAcctEntryId;   

        ELSIF varFsEntryType = c_WO and varSystemDefined = c_U_LINE and varArRevenueFlag = c_NO THEN

                SELECT DEBIT.ACCOUNT_NUMBER INTO varAccount              
                FROM DEBIT
                INNER JOIN ACCOUNTING_ENTRY
                    ON (ACCOUNTING_ENTRY.ACCTG_ENTRY_ID = DEBIT.ACCTG_ENTRY_ID)
                INNER JOIN DEBIT_RULE
                    ON (DEBIT_RULE.ACCTG_ENTRY_TYPE_ID = ACCOUNTING_ENTRY.ACCTG_ENTRY_TYPE_ID)    
                INNER JOIN GL_ACCOUNT
                    ON (GL_ACCOUNT.ACCOUNT_NUMBER = DEBIT_RULE.ACCOUNT_NUMBER)    
                INNER JOIN ACCOUNTING_CODE
                    ON (ACCOUNTING_CODE.ACCOUNTING_CODE_ID = ACCOUNTING_ENTRY.ACCOUNTING_CODE_ID)            
                WHERE ACCOUNTING_ENTRY.ACCTG_ENTRY_ID = varAcctEntryId;   
        END IF;
    
        RETURN varAccount;

    EXCEPTION
        WHEN OTHERS THEN
            -- Consider logging the error and then re-raise
            -- Removed RAISE, added return null.
            DBMS_OUTPUT.PUT_LINE('GET_FS_GL_REV_SRC : '||SQLERRM);
            
           LOG_CARS_ERROR(
                p_errorLevel    => '3',
                p_severity      => c_HIGH_SEVERITY,
                p_errorDetail   => 'FISCAL GET_FS_GL_REV_SRC function could not return account',
                p_errorCode     => '5000',
                p_errorMessage  => 'GET_FS_GL_REV_SRC : '||SQLERRM,
                p_dataSource    => c_CARS_DB
              );
    
            RETURN NULL;

    END GET_FS_GL_REV_SRC;     
    
    --
    -- Function return alt account as revenue source + agency source for A/R Revenue
    -- Returns other alt accounts based on A/R type
    --
    FUNCTION GET_FS_ALT_ACCT(varRevenueSrcCode VARCHAR2, varAgencySrcCode VARCHAR2, varTransactionCode VARCHAR2) RETURN VARCHAR2 IS
    
        varAltAcct VARCHAR2(10);
    BEGIN
        -- The Alternate Accounting for Regular and AR others
        IF      varTransactionCode IN ('445', '446', '447', '448') THEN 
                varAltAcct := '0138000000';
                
        ELSIF   varTransactionCode IN ('468', '456', '469')        THEN 
                varAltAcct := '0131900000';
                
        ELSE    
                varAltAcct:= varRevenueSrcCode || varAgencySrcCode;
        END IF;
        
        RETURN varAltAcct;
    
    EXCEPTION
            WHEN OTHERS THEN
            -- Consider logging the error and then re-raise
            -- Removed RAISE, added return null.
            DBMS_OUTPUT.PUT_LINE('GET_FS_ALT_ACCT : '||SQLERRM);
            
           LOG_CARS_ERROR(
                p_errorLevel    => '3',
                p_severity      => c_HIGH_SEVERITY,
                p_errorDetail   => 'FISCAL GET_FS_ALT_ACCT function could not return alt account',
                p_errorCode     => '5000',
                p_errorMessage  => 'GET_FS_ALT_ACCT : '||SQLERRM,
                p_dataSource    => c_CARS_DB
              );
    
            RETURN NULL;
    
    END GET_FS_ALT_ACCT; 
    
    FUNCTION GET_FS_SYSTEM_DEFINED(varRefValue VARCHAR2) RETURN VARCHAR2 IS
             
        varSysDef VARCHAR2(1);
    BEGIN

        SELECT  REFERENCE_CODE INTO varSysDef 
        FROM    REFERENCE_CODE_LIST 
        WHERE   REFERENCE_VALUE = varRefValue 
        AND     DOMAIN_NAME = c_DISTRIBUTION_LINE;
    
        RETURN varSysDef;

    EXCEPTION
        WHEN OTHERS THEN
            -- Consider logging the error and then re-raise
            -- Removed RAISE, added return null.
            DBMS_OUTPUT.PUT_LINE('GET_FS_SYSTEM_DEFINED : '||SQLERRM);
            
           LOG_CARS_ERROR(
                p_errorLevel    => '3',
                p_severity      => c_HIGH_SEVERITY,
                p_errorDetail   => 'FISCAL GET_FS_SYSTEM_DEFINED function could not return system defined',
                p_errorCode     => '5000',
                p_errorMessage  => 'GET_FS_SYSTEM_DEFINED : '||SQLERRM,
                p_dataSource    => c_CARS_DB
              );
    
            RETURN NULL;

    END GET_FS_SYSTEM_DEFINED;    
    
    FUNCTION GET_FS_LINE_NUMBER(
        varRootDocument VARCHAR2, 
        varProgramUnit  VARCHAR2) RETURN VARCHAR2 IS
        
        varLineNumber       INFAR006_OUTBOUND.ITEM%TYPE;
        varSuffixLength     NUMBER;
        varSuffixValue      VARCHAR2(3);
        varInvoiceLength    NUMBER;
        
    BEGIN
        varLineNumber   := NULL;
        varSuffixValue  := NULL;
        
        -- Find the FISCAL Invoice number. SIMS and PV Invoices suffix need to trimmed
        IF (varProgramUnit = c_PU_ART) OR (varProgramUnit = c_PU_EV) THEN
        
            varSuffixLength := 2;
            varSuffixValue  := SUBSTR(varRootDocument, -varSuffixLength);
            varInvoiceLength:= (LENGTH(varRootDocument) - varSuffixLength);
                        
        -- 5/11/2018: Vinay Patil: Per Liserin Lau or Accounting Unit has required to use the last three digit as suffix to determine the line number 0 or 1 for Pressure Vessels
        ELSIF (varProgramUnit = c_PU_PV) THEN
        
            varSuffixLength := 3;
            varSuffixValue  := SUBSTR(varRootDocument, -varSuffixLength);
            varInvoiceLength:= (LENGTH(varRootDocument) - varSuffixLength);
            
        END IF;

        IF (varSuffixValue IN ( '00','01','000','001')) THEN
            
           -- Get the Value without the suffix 
           varLineNumber := SUBSTR(varRootDocument, 0, varInvoiceLength );
           
        ELSE
           varLineNumber := varRootDocument; 
        
        END IF;
            
        RETURN varLineNumber;
        
    EXCEPTION
        WHEN OTHERS THEN
            -- Consider logging the error and then re-raise
            -- Removed RAISE, added return null.
            DBMS_OUTPUT.PUT_LINE('GET_FS_LINE_NUMBER : '||SQLERRM);
            
           LOG_CARS_ERROR(
                p_errorLevel    => '3',
                p_severity      => c_HIGH_SEVERITY,
                p_errorDetail   => 'FISCAL GET_FS_LINE_NUMBER function could not return line number',
                p_errorCode     => '5000',
                p_errorMessage  => 'GET_FS_LINE_NUMBER : '||SQLERRM,
                p_dataSource    => c_CARS_DB
              );
    
            RETURN NULL;
            
    END GET_FS_LINE_NUMBER;
    
    FUNCTION GET_FS_ITEM_LINE(varRootDocument VARCHAR2, varTransactionCode VARCHAR, varProgramUnit VARCHAR2) RETURN VARCHAR2 IS
    
       varItemLine          INFAR006_OUTBOUND.ITEM_LINE%TYPE;
       varLastRightLetter   VARCHAR2(1);
       varMiddleThree       VARCHAR2(3);
       
    BEGIN
        varItemLine := -1;
        
        -- Find Item Line to be sent to Fiscal
        IF (varProgramUnit = c_PU_CALOSHA) THEN

            --  Calosha A/R Contingents are Item Line 2
            --  Calosha A/R Others are Item line 3
            IF (varTransactionCode IN ('445', '446', '447', '448')) THEN
        
                varItemLine := 2;
        
            ELSIF (varTransactionCode IN ('456', '468', '469'))     THEN
        
                varItemLine := 3;
            ELSE 
                varItemLine := 1;
            
            END IF;
        
        --Rollups Invoices will always have Item Line as zero
        ELSIF varRootDocument LIKE 'R1%' THEN varItemLine := 0;
        
        --   ART A/R Others Fees are Item Line 2
        --   ART A/R Others Penalties are Item Line 3
        --   EV A/R Others Fees are Item Line 2
        --   EV A/R Others Penalties are Item Line 3
        --   PV A/R Others Fees are Item Line 2
        --   PV A/R Others Penalties are Item Line 3
        
        ELSIF (varProgramUnit IN  (c_PU_ART, c_PU_EV, c_PU_PV)) THEN

            -- Get the last letter or number in the invoice number
            varLastRightLetter := SUBSTR(varRootDocument, -1);
            
            --Fees 006 008 009 for PV 011
            IF (varTransactionCode IN ('456', '468', '469')) THEN
        
                -- increment the item line with 2
                varItemLine := TO_CHAR(TO_NUMBER(varLastRightLetter) + 2);
        
            ELSE
                 varItemLine := varLastRightLetter;
            END IF;
       
         END IF; 
        
        RETURN varItemLine;
    EXCEPTION
        WHEN OTHERS THEN
            -- Consider logging the error and then re-raise
            -- Removed RAISE, added return null.
            DBMS_OUTPUT.PUT_LINE('GET_FS_ITEM_LINE : '||SQLERRM);
            
           LOG_CARS_ERROR(
                p_errorLevel    => '3',
                p_severity      => c_HIGH_SEVERITY,
                p_errorDetail   => 'FISCAL GET_FS_ITEM_LINE function could not return item line',
                p_errorCode     => '5000',
                p_errorMessage  => 'GET_FS_ITEM_LINE : '||SQLERRM,
                p_dataSource    => c_CARS_DB
              );
    
            RETURN NULL;
            
    END GET_FS_ITEM_LINE; 
    
    -- Function gets Entry Type Code for a 900 Event
    -- Currently not being transmitted to FISCAL per Accounting Requirement
    FUNCTION GET_FS_ENT_TYPE_REVERSE(p_entry_type VARCHAR2) RETURN VARCHAR2 AS

        v_new_entry_type FS_ENTRY_TYPE.ENTRY_TYPE_CODE%TYPE := NULL;

    BEGIN
        
        IF p_entry_type = c_DR THEN
            v_new_entry_type := c_CR;
        
        ELSIF p_entry_type = c_CR THEN
            v_new_entry_type := c_DR;
        
        ELSIF p_entry_type = c_CRYEC THEN
            v_new_entry_type := c_DRYEC;
        
        ELSIF p_entry_type = c_DRYEC THEN
            v_new_entry_type := c_CRYEC;

        END IF;
            
        RETURN v_new_entry_type;

    EXCEPTION
        WHEN OTHERS THEN
            -- Consider logging the error and then re-raise
            -- Removed RAISE, added return null.
            DBMS_OUTPUT.PUT_LINE('GET_FS_ENT_TYPE_REVERSE : '||SQLERRM);
            
           LOG_CARS_ERROR(
                p_errorLevel    => '3',
                p_severity      => c_HIGH_SEVERITY,
                p_errorDetail   => 'FISCAL GET_FS_ENT_TYPE_REVERSE function could not return v_new_entry_type',
                p_errorCode     => '5000',
                p_errorMessage  => 'GET_FS_ENT_TYPE_REVERSE : '||SQLERRM,
                p_dataSource    => c_CARS_DB
              );
    
            RETURN NULL;
            
    END GET_FS_ENT_TYPE_REVERSE;
    
    -- Function gets Entry Reason Code for a 900 Event
    -- Currently not being transmitted to FISCAL per Accounting Requirement
    FUNCTION GET_FS_ENT_RSN_REVERSE(p_entry_reason VARCHAR2 ) RETURN VARCHAR2 AS

        v_new_entry_reason FS_ENTRY_REASON_TYPE.ENTRY_REASON_CODE%TYPE;

    BEGIN
        
        IF p_entry_reason = 'INCRS' THEN
            v_new_entry_reason := 'DECRS';
        
        ELSIF p_entry_reason = 'DECRS' THEN
            v_new_entry_reason := 'INCRS';
        
        ELSIF p_entry_reason = 'ERROR' THEN
            v_new_entry_reason := 'MISC';
        
        ELSIF p_entry_reason = 'MISC' THEN
            v_new_entry_reason := 'ERROR';
        
        ELSIF p_entry_reason = 'RCLAS' THEN
            v_new_entry_reason := 'RVREV';
        
        ELSIF p_entry_reason = 'RVREV' THEN
            v_new_entry_reason := 'RCLAS';
        
        ELSIF p_entry_reason = 'AROT' THEN
            v_new_entry_reason := 'WAIVE';
        
        ELSIF p_entry_reason = 'WAIVE' THEN
            v_new_entry_reason := 'AROT';
        
        ELSIF p_entry_reason = 'UNCOL' THEN
            v_new_entry_reason := 'AROT';
        
        ELSIF p_entry_reason = 'APEAL' THEN
            v_new_entry_reason := 'INCRS';
        
        ELSIF p_entry_reason = 'RCLAS' THEN
            v_new_entry_reason := 'RVREV';
        
        ELSIF p_entry_reason = 'RVREV' THEN
            v_new_entry_reason := 'RCLAS';
       
        ELSE 
            v_new_entry_reason := p_entry_reason;
        END IF;
            
        RETURN v_new_entry_reason;

    EXCEPTION
        WHEN OTHERS THEN
            -- Consider logging the error and then re-raise
            -- Removed RAISE, added return null.
            DBMS_OUTPUT.PUT_LINE('GET_FS_ENT_RSN_REVERSE : '|| SQLERRM);
            
           LOG_CARS_ERROR(
                p_errorLevel    => '3',
                p_severity      => c_HIGH_SEVERITY,
                p_errorDetail   => 'FISCAL GET_FS_ENT_RSN_REVERSE function could not return entry reason',
                p_errorCode     => '5000',
                p_errorMessage  => 'GET_FS_ENT_RSN_REVERSE : '|| SQLERRM,
                p_dataSource    => c_CARS_DB
              );
    
            RETURN NULL;
            
    END GET_FS_ENT_RSN_REVERSE;

    FUNCTION FUNC_GET_PRIOR_FISCAL_YEAR(varRootDoc IN VARCHAR2) RETURN VARCHAR2 IS
    /******************************************************************************
       NAME:       FUNC_GET_PRIOR_FISCAL_YEAR
       PURPOSE:    Convert the given root document event date to fiscal year name.

       Ver        Date        Author           Description
       ---------  ----------  ---------------  ------------------------------------
       1.0        4/25/2016   Terence Pan         1. Created this function.
    ******************************************************************************/
        varEventDate        DATE;
        varFiscalYear       VARCHAR2(4);
        varPyFiscalYear     VARCHAR2(4);
        tempMonth           VARCHAR2(2);
        tempPyMonth         VARCHAR2(2);
        tempYear            VARCHAR2(4);
        tempPyYear          VARCHAR2(4);
        tempNumberMonth     NUMBER;
        tempPyNumberMonth   NUMBER;
        tempFY              NUMBER;
        tempPyFY            NUMBER;
        varLevel            NUMBER;
        varMessage          VARCHAR2(200);
        v_Sysdate           DATE := SYSDATE;

    BEGIN

        IF (varRootDoc IS NOT NULL) THEN
        
            --SELECT E.EVENT_DATE into varEventDate
            --FROM EVENT E INNER JOIN EVENT_TYPE ET
            --ON E.EVENT_TYPE_ID = ET.EVENT_TYPE_ID WHERE Level = 1 AND E.CURRENT_DOCUMENT = varRootDoc
            --CONNECT BY NOCYCLE PRIOR E.REFERENCE_DOCUMENT = E.CURRENT_DOCUMENT  ;

            -- 5/24/2018, Vinay Patil: Get the Event Date based on AR setup event.
            SELECT  EVENT.EVENT_DATE 
            INTO    varEventDate
            FROM    EVENT
                INNER JOIN EVENT_TYPE       ON EVENT.EVENT_TYPE_ID       = EVENT_TYPE.EVENT_TYPE_ID
            WHERE EVENT_TYPE.EVENT_TYPE_CODE IN (c_EVENT_010, c_EVENT_015)
              AND EVENT.CURRENT_DOCUMENT  = varRootDoc
              AND EVENT.AR_ROOT_DOCUMENT  = varRootDoc;
          
            varFiscalYear   := null;
            tempMonth       := to_char(varEventDate, 'MM');
            tempNumberMonth := to_number(tempMonth);
            tempYear        := to_char(varEventDate, 'YYYY');
            tempFY          := to_number(tempYear);

            -- Previous Finacical Year        
            if(tempNumberMonth < 7) then
                tempFY := tempFY - 1;
            end if;
            
            tempPyMonth         := to_char(v_Sysdate, 'MM');
            tempPyNumberMonth   := to_number(tempPyMonth);
            tempPyYear          := to_char(v_Sysdate, 'YYYY');
            tempPyFY            := to_number(tempPyYear) - 1;
            
            -- Previous Finacical Year        
            if(tempPyNumberMonth < 7) then
                tempPyFY := tempPyFY - 1;
            end if;
            
            if(tempFY < tempPyFY) then
                varFiscalYear := to_char(tempPyFY);
            else
                varFiscalYear := to_char(tempFY);
            end if;

        ELSE
            varFiscalYear   := NULL;
            varMessage      := 'FUNC_GET_PRIOR_FISCAL_YEAR: Invalid input parameter. Root Document '||varRootDoc||' must have a value';
            DBMS_OUTPUT.PUT_LINE(varMessage);

        END IF;
                
        RETURN varFiscalYear;

    EXCEPTION
        WHEN OTHERS THEN
            -- Consider logging the error and then re-raise
            varFiscalYear := NULL;
            varMessage    := 'FUNC_GET_PRIOR_FISCAL_YEAR: '||' varRootDoc '||varRootDoc||' '||SQLERRM;
            DBMS_OUTPUT.PUT_LINE(varMessage);

           LOG_CARS_ERROR(
                p_errorLevel    => '3',
                p_severity      => c_HIGH_SEVERITY,
                p_errorDetail   => 'FISCAL FUNC_GET_PRIOR_FISCAL_YEAR function could not return financial year',
                p_errorCode     => '5000',
                p_errorMessage  => varMessage,
                p_dataSource    => c_CARS_DB
              );

            --RAISE;
            RETURN varFiscalYear;
                        
    END FUNC_GET_PRIOR_FISCAL_YEAR;
    
    PROCEDURE UPDATE_STATUS_BY_ID(
        varStatus       ACCOUNTING_ENTRY_STATUS.FS_PROCESS_STATUS%TYPE,
        varBatchDate    DATE, 
        varAcctgEntryId NUMBER) AS
        
        varErrorMsg     VARCHAR2(500);
    BEGIN
    
        UPDATE ACCOUNTING_ENTRY_STATUS 
        SET FS_PROCESS_STATUS   = varStatus, 
            FS_PROCESS_DATE     = varBatchDate, -- does not have time.
            MODIFIED_BY         = c_USER, 
            MODIFIED_DATE       = SYSDATE
        WHERE ACCTG_ENTRY_ID = varAcctgEntryId;
    
    EXCEPTION
        WHEN OTHERS THEN
            -- Consider logging the error and then re-raise
            
            varErrorMsg := 'UPDATE_STATUS_BY_ID: Could not UPDATE ACCOUNTING_ENTRY_STATUS for ' || varStatus ||
                           ' STATUS on Batch Date ' || varBatchDate || ', and Accounting Entry Id ' || varAcctgEntryId||' '||SQLERRM;
                
            DBMS_OUTPUT.PUT_LINE('UPDATE_BY_STATUS_ID Error: ' || varErrorMsg);
     
            LOG_CARS_ERROR(
                    p_errorLevel    => '3',
                    p_severity      => c_HIGH_SEVERITY,
                    p_errorDetail   => 'FISCAL UPDATE_STATUS_BY_ID procedure could not update status',
                    p_errorCode     => '5000',
                    p_errorMessage  => varErrorMsg,
                    p_dataSource    => c_CARS_DB
                  );
                  
    END UPDATE_STATUS_BY_ID;
    
    PROCEDURE UPD_EVENT_900_STATUS(
                batchDate           DATE,
                P_SUCCESS_FLAG  OUT VARCHAR2,
                P_MESSAGE       OUT VARCHAR2)     IS
                
       V_SUCCESS_FLAG   VARCHAR2(1) := c_NO;
       V_MESSAGE        VARCHAR2(500);
       
    BEGIN
        UPDATE ACCOUNTING_ENTRY_STATUS SET FS_PROCESS_STATUS = c_STATUS_NOT_XMIT
        WHERE acctg_entry_id IN 
            (SELECT AE.acctg_entry_id
                FROM ACCOUNTING_ENTRY AE
                    INNER JOIN ACCOUNTING_ENTRY_STATUS AES
                        ON AE.ACCTG_ENTRY_ID = AES.ACCTG_ENTRY_ID
                    INNER JOIN ACCOUNTING_ENTRY_TYPE AET
                        ON AET.ACCTG_ENTRY_TYPE_ID = AE.ACCTG_ENTRY_TYPE_ID
                    INNER JOIN ACCTG_TRANSACT_EVENT_ASSOC ATEA
                        ON ATEA.ACCTG_TRANSACTION_ID = AE.ACCTG_TRANSACTION_ID
                    INNER JOIN EVENT
                        ON EVENT.EVENT_ID = ATEA.EVENT_ID
                    INNER JOIN EVENT_TYPE ET
                        ON EVENT.EVENT_TYPE_ID  = ET.EVENT_TYPE_ID
                WHERE   ET.EVENT_TYPE_CODE      = c_EVENT_900
                  AND   trunc(AES.CREATED_DATE) <= trunc(batchDate)
                  AND   AES.FS_PROCESS_STATUS   = c_STATUS_NEW);

        V_SUCCESS_FLAG     := c_YES;
        V_MESSAGE          := 'UPD_EVENT_WO_STATUS: Updated Accounting Entry Status records to '||c_STATUS_NOT_XMIT||' for invoices 900 events : '|| SQL%ROWCOUNT||' for batch date '||batchDate;

        P_SUCCESS_FLAG     := V_SUCCESS_FLAG;
        P_MESSAGE          := V_MESSAGE;

        DBMS_OUTPUT.PUT_LINE('UPD_INFAR006_ZERO_BAL : V_SUCCESS_FLAG = '||V_SUCCESS_FLAG||' '||V_MESSAGE); 
    
    EXCEPTION
        WHEN OTHERS THEN 

            V_SUCCESS_FLAG     := c_NO;
            V_MESSAGE          := 'Failure occured in UPD_EVENT_900_STATUS: ' || SQLERRM;


            P_SUCCESS_FLAG     := V_SUCCESS_FLAG;
            P_MESSAGE          := V_MESSAGE;

	    LOG_CARS_ERROR(p_errorLevel    => '3',
			   p_severity      => c_HIGH_SEVERITY,
			   p_errorDetail   => 'FISCAL UPD_EVENT_900_STATUS procedure did not succeed',
			   p_errorCode     => '5000',
			   p_errorMessage  => V_MESSAGE,
			   p_dataSource    => c_CARS_DB
			  );  

            DBMS_OUTPUT.PUT_LINE(' V_SUCCESS_FLAG = '||V_SUCCESS_FLAG||' '||V_MESSAGE );
                
    END UPD_EVENT_900_STATUS;
    
    PROCEDURE UPD_EVENT_WO_STATUS(
                batchDate           DATE,
                P_SUCCESS_FLAG   OUT VARCHAR2,
                P_MESSAGE        OUT VARCHAR2) IS
                
       V_SUCCESS_FLAG   VARCHAR2(1) := c_NO;
       V_MESSAGE        VARCHAR2(500);
       
    BEGIN
        UPDATE  ACCOUNTING_ENTRY_STATUS 
        SET     FS_PROCESS_STATUS = c_STATUS_NOT_XMIT
        WHERE acctg_entry_id IN 
            (SELECT AE.acctg_entry_id
                FROM ACCOUNTING_ENTRY AE
                    INNER JOIN ACCOUNTING_ENTRY_STATUS AES
                        ON AE.ACCTG_ENTRY_ID = AES.ACCTG_ENTRY_ID
                    INNER JOIN ACCOUNTING_ENTRY_TYPE AET
                        ON AET.ACCTG_ENTRY_TYPE_ID = AE.ACCTG_ENTRY_TYPE_ID
                    INNER JOIN ACCTG_TRANSACT_EVENT_ASSOC ATEA
                        ON ATEA.ACCTG_TRANSACTION_ID = AE.ACCTG_TRANSACTION_ID
                    INNER JOIN EVENT
                        ON EVENT.EVENT_ID = ATEA.EVENT_ID
                    INNER JOIN EVENT_TYPE ET
                        ON EVENT.EVENT_TYPE_ID = ET.EVENT_TYPE_ID
                WHERE   ET.EVENT_TYPE_CODE      IN ('135', '160')
                  AND   trunc(AES.CREATED_DATE)<= trunc(batchDate)
                  AND   AES.FS_PROCESS_STATUS   = c_STATUS_NEW);

        V_SUCCESS_FLAG     := c_YES;
        V_MESSAGE          := 'UPD_EVENT_WO_STATUS: Updated Accounting Entry Status records to '||c_STATUS_NOT_XMIT||' for invoices 135 and 160 events : '|| SQL%ROWCOUNT||' for batch date '||batchDate;

        P_SUCCESS_FLAG     := V_SUCCESS_FLAG;
        P_MESSAGE          := V_MESSAGE;

        DBMS_OUTPUT.PUT_LINE('UPD_EVENT_WO_STATUS : V_SUCCESS_FLAG = '||V_SUCCESS_FLAG||' '||V_MESSAGE); 


    EXCEPTION
        WHEN OTHERS THEN 

            V_SUCCESS_FLAG     := c_NO;
            V_MESSAGE          := 'Failure occured in UPD_EVENT_WO_STATUS: ' || SQLERRM;

            P_SUCCESS_FLAG     := V_SUCCESS_FLAG;
            P_MESSAGE          := V_MESSAGE;

	    LOG_CARS_ERROR(p_errorLevel    => '3',
			   p_severity      => c_HIGH_SEVERITY,
			   p_errorDetail   => 'FISCAL UPD_EVENT_WO_STATUS procedure did not succeed',
			   p_errorCode     => '5000',
			   p_errorMessage  => V_MESSAGE,
			   p_dataSource    => c_CARS_DB
			  );  

            DBMS_OUTPUT.PUT_LINE(' V_SUCCESS_FLAG = '||V_SUCCESS_FLAG||' '||V_MESSAGE );
                
    END UPD_EVENT_WO_STATUS;
    
    PROCEDURE FS_PROCESS_INFAR001(
            varBatchId      NUMBER, 
            varBatchDateStr BATCH.BATCH_DATE%TYPE, 
            varProgramUnit  EVENT_TYPE.PROGRAM_UNIT_CODE%TYPE) AS
 
    BEGIN
        
        GET_INFAR001_DATA(varBatchId, varBatchDateStr, varProgramUnit, c_TC_101, c_NO);
        GET_INFAR001_DATA(varBatchId, varBatchDateStr, varProgramUnit, c_TC_101, c_REVERSE);
        GET_INFAR001_DATA(varBatchId, varBatchDateStr, varProgramUnit, c_TC_142, c_NO);
        GET_INFAR001_DATA(varBatchId, varBatchDateStr, varProgramUnit, c_TC_142, c_REVERSE);
            
    END FS_PROCESS_INFAR001;
    
    PROCEDURE FS_PROCESS_INFAR006_SETUP (
            varBatchId          NUMBER, 
            varBatchDateStr     BATCH.BATCH_DATE%TYPE, 
            varProgramUnit      EVENT_TYPE.PROGRAM_UNIT_CODE%TYPE, 
            varLastBatchDate    DATE) AS
            
        V_SUCCESS_FLAG                       VARCHAR2(1);
        V_MESSAGE                            VARCHAR2(500);            
    BEGIN
        -- TC 120 --
      GET_INFAR006_DATA(varBatchId, varBatchDateStr,varProgramUnit, '120', '010', varLastBatchDate,  V_SUCCESS_FLAG, V_MESSAGE);
          
      GET_INFAR006_DATA(varBatchId, varBatchDateStr,varProgramUnit, '120', '130', varLastBatchDate,  V_SUCCESS_FLAG, V_MESSAGE); 
          
      GET_INFAR006_DATA(varBatchId, varBatchDateStr,varProgramUnit, '120', '530', varLastBatchDate,  V_SUCCESS_FLAG, V_MESSAGE);

      -- TC 445 --
      GET_INFAR006_DATA(varBatchId, varBatchDateStr,varProgramUnit, '445', '520', varLastBatchDate,  V_SUCCESS_FLAG, V_MESSAGE);
           
      GET_INFAR006_DATA(varBatchId, varBatchDateStr,varProgramUnit, '445', '525', varLastBatchDate,  V_SUCCESS_FLAG, V_MESSAGE);          
      
      -- TC 446
      GET_INFAR006_DATA(varBatchId, varBatchDateStr,varProgramUnit, '446', '130', varLastBatchDate,  V_SUCCESS_FLAG, V_MESSAGE); 
          
      GET_INFAR006_DATA(varBatchId, varBatchDateStr,varProgramUnit, '446', '516', varLastBatchDate,  V_SUCCESS_FLAG, V_MESSAGE);
          
        -- TC 468 --
      GET_INFAR006_DATA(varBatchId, varBatchDateStr,varProgramUnit, '468', '015', varLastBatchDate,  V_SUCCESS_FLAG, V_MESSAGE);

      GET_INFAR006_DATA(varBatchId, varBatchDateStr,varProgramUnit, '468', '510', varLastBatchDate,  V_SUCCESS_FLAG, V_MESSAGE);

      GET_INFAR006_DATA(varBatchId, varBatchDateStr,varProgramUnit, '468', '515', varLastBatchDate,  V_SUCCESS_FLAG, V_MESSAGE);

      GET_INFAR006_DATA(varBatchId, varBatchDateStr,varProgramUnit, '468', '516', varLastBatchDate,  V_SUCCESS_FLAG, V_MESSAGE);
          
    EXCEPTION
       WHEN OTHERS THEN
                    
            DBMS_OUTPUT.PUT_LINE('Failure occured in FS_PROCESS_INFAR006_SETUP :' ||SQLERRM);

            LOG_CARS_ERROR(
                p_errorLevel    => '3',
                p_severity      => c_HIGH_SEVERITY,
                p_errorDetail   => 'Failure occured in FS_PROCESS_INFAR006_SETUP :' ||SQLERRM,
                p_errorCode     => '5000',
                p_errorMessage  => null ,
                p_dataSource    => c_CARS_DB
                );             
           
    END FS_PROCESS_INFAR006_SETUP;
    
    PROCEDURE FS_PROCESS_INFAR006_ADJUST (
            varBatchId          NUMBER, 
            varBatchDateStr     BATCH.BATCH_DATE%TYPE, 
            varProgramUnit      EVENT_TYPE.PROGRAM_UNIT_CODE%TYPE, 
            varLastBatchDate    DATE) AS
            
        V_SUCCESS_FLAG                       VARCHAR2(1);
        V_MESSAGE                            VARCHAR2(500);            
    BEGIN
      -- TC 120
      GET_INFAR006_DATA(varBatchId, varBatchDateStr,varProgramUnit, '120', '165', varLastBatchDate,    V_SUCCESS_FLAG, V_MESSAGE);        
      
      -- TC 446 --   
      GET_INFAR006_DATA(varBatchId, varBatchDateStr,varProgramUnit, '446', '530', varLastBatchDate,    V_SUCCESS_FLAG, V_MESSAGE);       
      
      -- TC 447 --
      GET_INFAR006_DATA(varBatchId, varBatchDateStr,varProgramUnit, '447', '535', varLastBatchDate,    V_SUCCESS_FLAG, V_MESSAGE); 

      GET_INFAR006_DATA(varBatchId, varBatchDateStr,varProgramUnit, '447', '537', varLastBatchDate,    V_SUCCESS_FLAG, V_MESSAGE); 

      -- TC 448 --
      GET_INFAR006_DATA(varBatchId, varBatchDateStr,varProgramUnit, '448', '125', varLastBatchDate,    V_SUCCESS_FLAG, V_MESSAGE); 

      GET_INFAR006_DATA(varBatchId, varBatchDateStr,varProgramUnit, '448', '510', varLastBatchDate,    V_SUCCESS_FLAG, V_MESSAGE); 

      GET_INFAR006_DATA(varBatchId, varBatchDateStr,varProgramUnit, '448', '536', varLastBatchDate,    V_SUCCESS_FLAG, V_MESSAGE);
          
      GET_INFAR006_DATA(varBatchId, varBatchDateStr,varProgramUnit, '448', '538', varLastBatchDate,    V_SUCCESS_FLAG, V_MESSAGE);       

      -- TC 456 --
      GET_INFAR006_DATA(varBatchId, varBatchDateStr,varProgramUnit, '456', '150', varLastBatchDate,    V_SUCCESS_FLAG, V_MESSAGE); 

      GET_INFAR006_DATA(varBatchId, varBatchDateStr,varProgramUnit, '456', '155', varLastBatchDate,    V_SUCCESS_FLAG, V_MESSAGE); 

      GET_INFAR006_DATA(varBatchId, varBatchDateStr,varProgramUnit, '456', '265', varLastBatchDate,    V_SUCCESS_FLAG, V_MESSAGE);          

      -- Raman Nakarmi: 05/08/2018  : Added EVENT 270 to GET_INFAR006_DATA 
      GET_INFAR006_DATA(varBatchId, varBatchDateStr,varProgramUnit, '456', '270, 325', varLastBatchDate, V_SUCCESS_FLAG, V_MESSAGE); 

      GET_INFAR006_DATA(varBatchId, varBatchDateStr,varProgramUnit, '456', '275, 330', varLastBatchDate, V_SUCCESS_FLAG, V_MESSAGE);
    
      GET_INFAR006_DATA(varBatchId, varBatchDateStr,varProgramUnit, '456', '276, 331', varLastBatchDate, V_SUCCESS_FLAG, V_MESSAGE);
          
      GET_INFAR006_DATA(varBatchId, varBatchDateStr,varProgramUnit, '456', '342', varLastBatchDate,    V_SUCCESS_FLAG, V_MESSAGE);
    
      GET_INFAR006_DATA(varBatchId, varBatchDateStr,varProgramUnit, '456', '343', varLastBatchDate,    V_SUCCESS_FLAG, V_MESSAGE);
          
      GET_INFAR006_DATA(varBatchId, varBatchDateStr,varProgramUnit, '456', '525', varLastBatchDate,    V_SUCCESS_FLAG, V_MESSAGE); 
    
      GET_INFAR006_DATA(varBatchId, varBatchDateStr,varProgramUnit, '456', '537', varLastBatchDate,    V_SUCCESS_FLAG, V_MESSAGE); 
                
      -- TC 460 --
      GET_INFAR006_DATA(varBatchId, varBatchDateStr,varProgramUnit, '460', '115', varLastBatchDate,    V_SUCCESS_FLAG, V_MESSAGE);
          
      -- Disabled until further instructions from accounting
      --GET_INFAR006_DATA(varBatchId, varBatchDateStr,varProgramUnit, '460', '160', varLastBatchDate,    V_SUCCESS_FLAG, V_MESSAGE);        
    
      GET_INFAR006_DATA(varBatchId, varBatchDateStr,varProgramUnit, '460', '520', varLastBatchDate,    V_SUCCESS_FLAG, V_MESSAGE); 
    
      GET_INFAR006_DATA(varBatchId, varBatchDateStr,varProgramUnit, '460', '515', varLastBatchDate,    V_SUCCESS_FLAG, V_MESSAGE);             
    
      GET_INFAR006_DATA(varBatchId, varBatchDateStr,varProgramUnit, '460', '535', varLastBatchDate,    V_SUCCESS_FLAG, V_MESSAGE);
           
      -- TC 466--
      GET_INFAR006_DATA(varBatchId, varBatchDateStr,varProgramUnit, '466', '110', varLastBatchDate,    V_SUCCESS_FLAG, V_MESSAGE); 
    
      GET_INFAR006_DATA(varBatchId, varBatchDateStr,varProgramUnit, '466', '536', varLastBatchDate,    V_SUCCESS_FLAG, V_MESSAGE); 
          
      -- TC 468--
      GET_INFAR006_DATA(varBatchId, varBatchDateStr,varProgramUnit, '468', '145', varLastBatchDate,    V_SUCCESS_FLAG, V_MESSAGE); 
    
      GET_INFAR006_DATA(varBatchId, varBatchDateStr,varProgramUnit, '468', '538', varLastBatchDate,    V_SUCCESS_FLAG, V_MESSAGE);           
          
      -- TC 469 -- Disabled until further instructions from accounting
      --GET_INFAR006_DATA(varBatchId, varBatchDateStr,varProgramUnit, '469', '135', varLastBatchDate,    V_SUCCESS_FLAG, V_MESSAGE);                     
           
    EXCEPTION
       WHEN OTHERS THEN
                    
            DBMS_OUTPUT.PUT_LINE('Failure occured in FS_PROCESS_INFAR006_ADJUST :' ||SQLERRM);

            LOG_CARS_ERROR(
                p_errorLevel    => '3',
                p_severity      => c_HIGH_SEVERITY,
                p_errorDetail   => 'FISCAL FS_PROCESS_INFAR006_ADJUST procedure did not succeed',
                p_errorCode     => '5000',
                p_errorMessage  => 'Failure occured in FS_PROCESS_INFAR006_ADJUST :' ||SQLERRM ,
                p_dataSource    => c_CARS_DB
                );             
           
    END FS_PROCESS_INFAR006_ADJUST;
    
    PROCEDURE INFAR001_UPDATE_BATCH(
        varBatchId      NUMBER, 
        varBatchDateStr BATCH.BATCH_DATE%TYPE) AS
                
        varBatchCount   NUMBER;
        varTotalAmt     NUMBER;

        V_STATUS        INFAR001_OUTBOUND.STATUS%TYPE := c_STATUS_NEW;
        V_SUCCESS_FLAG  VARCHAR2(1);
        V_MESSAGE       VARCHAR2(500);
                    
    BEGIN
        SELECT  NVL(SUM(IO.CONTROL_AMT),0), 
                NVL(COUNT(IO.DEPOSIT_ID),0) 
        INTO    varTotalAmt, 
                varBatchCount
        FROM    INFAR001_OUTBOUND  IO
        WHERE   IO.BATCH_ID     = varBatchId 
        AND     IO.FS_ROW_ID    = c_DC_ROW_ID;
    
        DBMS_OUTPUT.PUT_LINE(varBatchCount || ' ' || varTotalAmt);
           
       IF (varBatchCount > 0 ) THEN
       
           DBMS_OUTPUT.PUT_LINE('Update Total Batch Count and Total Amount for INFAR001 in BATCH table.');
           
           UPDATE   BATCH 
           SET      BATCH_COUNT         = varBatchCount,
                    TOTAL_BATCH_AMOUNT  = varTotalAmt 
           WHERE    BATCH_ID = varBatchId;  
           
           --This is a header line, do not have to set status here, just total.
           UPDATE   INFAR001_OUTBOUND
           SET      DEPOSIT_CNT = varBatchCount, 
                    TOTAL_AMT   = varTotalAmt, 
                    STATUS      = V_STATUS
           WHERE    BATCH_ID   = varBatchId 
           AND      FS_ROW_ID  = c_FH_ROW_ID;

            V_MESSAGE := 'INFAR001_UPDATE_BATCH: Updated Batch '||varBatchId||' total amount '||varTotalAmt||' batch count '||varBatchCount||' and INFAR001 '|| c_FH_ROW_ID||' record status to '|| V_STATUS||' total amount '||varTotalAmt||' batch count '||varBatchCount; 
                       
        --if file is empty, then update batch status to 'N' and Status on infar001_outbound header to 'NOT_TRANSMITTED'
        ELSE 
            V_STATUS := c_STATUS_NOT_XMIT;
            
            UPDATE BATCH 
            SET STATUS      = c_BATCH_NOT_XMIT
            WHERE BATCH_ID  = varBatchId;
            
            UPDATE INFAR001_OUTBOUND
            SET STATUS      = c_STATUS_NOT_XMIT
            WHERE BATCH_ID  = varBatchId 
            AND   FS_ROW_ID = c_FH_ROW_ID;

            V_MESSAGE := 'INFAR001_UPDATE_BATCH: Updated Batch '||varBatchId||' to '||V_STATUS||' and '|| SQL%ROWCOUNT||' INFAR001 '|| c_FH_ROW_ID||' records status to '|| V_STATUS;            
       END IF;    
       
        V_SUCCESS_FLAG     := c_YES;
        DBMS_OUTPUT.PUT_LINE('INFAR001_UPDATE_BATCH : V_SUCCESS_FLAG = '||V_SUCCESS_FLAG||' '||V_MESSAGE); 
        

    EXCEPTION
        WHEN OTHERS THEN
                            
            V_SUCCESS_FLAG     := c_NO;
            V_MESSAGE          := 'Failure occured in INFAR001_UPDATE_BATCH :' ||SQLERRM;

            LOG_CARS_ERROR(
                p_errorLevel    => '3',
                p_severity      => c_HIGH_SEVERITY,
                p_errorDetail   => 'FISCAL INFAR001_UPDATE_BATCH procedure did not succeed',
                p_errorCode     => '5000',
                p_errorMessage  => V_MESSAGE ,
                p_dataSource    => c_CARS_DB
                );             
           
            DBMS_OUTPUT.PUT_LINE(' V_SUCCESS_FLAG = '||V_SUCCESS_FLAG||' '||V_MESSAGE );
            
    END INFAR001_UPDATE_BATCH;
    
    PROCEDURE INFAR006_UPDATE_BATCH(varBatchId NUMBER) AS
        varBatchCount   NUMBER;
        varTotalAmt     NUMBER;    
        
        V_SUCCESS_FLAG  VARCHAR2(1);
        V_MESSAGE       VARCHAR2(500);

    BEGIN
    
       SELECT   COUNT(BATCH_ID), SUM(ENTRY_AMT) 
       INTO     varBatchCount, varTotalAmt
       FROM     INFAR006_OUTBOUND
       WHERE    BATCH_ID        = varBatchId
       AND      SYSTEM_DEFINED  = c_A_LINE;

       -- 5/24/2018, Vinay Patil: Removed the Left Padding of zeros to the count and amount 
       IF (varBatchCount > 0 ) THEN
       
           UPDATE BATCH 
           SET BATCH_COUNT          = TO_CHAR(varBatchCount),
               TOTAL_BATCH_AMOUNT   = TO_CHAR(varTotalAmt) 
           WHERE BATCH_ID = varBatchId;

           V_MESSAGE := 'INFAR006_UPDATE_BATCH: Updated Batch '||varBatchId||' varBatchCount '|| varBatchCount||' varTotalAmt '|| varTotalAmt;  
           
       ELSE 
       -- if the batch has no children
           UPDATE BATCH 
           SET BATCH_COUNT          = TO_CHAR(varBatchCount),
               TOTAL_BATCH_AMOUNT   = TO_CHAR(varTotalAmt),
               STATUS               = c_NO
           WHERE BATCH_ID = varBatchId; 
           
           V_MESSAGE := 'INFAR006_UPDATE_BATCH: Updated Batch '||varBatchId||' to '||c_NO||' and '|| SQL%ROWCOUNT||' varBatchCount '|| varBatchCount||' varTotalAmt '|| varTotalAmt;  

       END IF;  

        V_SUCCESS_FLAG := c_YES;

       DBMS_OUTPUT.PUT_LINE('V_SUCCESS_FLAG = '||V_SUCCESS_FLAG||' '||V_MESSAGE);
           
    EXCEPTION
        WHEN OTHERS THEN

            V_SUCCESS_FLAG := c_NO;
            V_MESSAGE := 'INFAR006_UPDATE_BATCH : '||'Batch ID: ' || varBatchId||' '||SQLERRM;
            
            DBMS_OUTPUT.PUT_LINE('V_SUCCESS_FLAG = '||V_SUCCESS_FLAG||' '||V_MESSAGE);

            LOG_CARS_ERROR(
                p_errorLevel    => '3',
                p_severity      => c_HIGH_SEVERITY,
                p_errorDetail   => 'FISCAL INFAR006_UPDATE_BATCH procedure did not succeed',
                p_errorCode     => '5000',
                p_errorMessage  => V_MESSAGE ,
                p_dataSource    => c_CARS_DB
				);             

    END INFAR006_UPDATE_BATCH;
    
    PROCEDURE UPD_INFAR006_ZERO_BAL (
                batchDate  DATE,
                P_SUCCESS_FLAG    OUT VARCHAR2,
                P_MESSAGE         OUT VARCHAR2) IS

       V_SUCCESS_FLAG   VARCHAR2(1)     := c_NO;
       V_MESSAGE        VARCHAR2(500);
       
    BEGIN
    
        -- Zero balance Invoices cannot be transmitted to Fiscal as they will be Rejected.
        UPDATE  ACCOUNTING_ENTRY_STATUS 
        SET     FS_PROCESS_STATUS   = c_STATUS_NOT_XMIT, 
                FS_PROCESS_DATE     = batchDate
        WHERE ACCTG_ENTRY_ID IN 
            (SELECT AE.ACCTG_ENTRY_ID
                FROM ACCOUNTING_ENTRY AE
                    INNER JOIN ACCOUNTING_ENTRY_STATUS AES
                        ON AE.ACCTG_ENTRY_ID = AES.ACCTG_ENTRY_ID
                    INNER JOIN ACCOUNTING_ENTRY_TYPE AET
                        ON AET.ACCTG_ENTRY_TYPE_ID = AE.ACCTG_ENTRY_TYPE_ID
                    INNER JOIN ACCTG_TRANSACT_EVENT_ASSOC ATEA
                        ON ATEA.ACCTG_TRANSACTION_ID = AE.ACCTG_TRANSACTION_ID
                    INNER JOIN EVENT
                        ON EVENT.EVENT_ID = ATEA.EVENT_ID
                    INNER JOIN EVENT_TYPE ET
                        ON EVENT.EVENT_TYPE_ID = ET.EVENT_TYPE_ID
                WHERE   AE.AMOUNT             = 0 
                AND     trunc(AES.CREATED_DATE)     <= trunc(batchDate) 
                AND     AES.FS_PROCESS_STATUS = c_STATUS_NEW
                );

        V_SUCCESS_FLAG     := c_YES;
        V_MESSAGE          := 'UPD_INFAR006_ZERO_BAL: Updated Accounting Entry Status records for zero balance invoices: '|| SQL%ROWCOUNT||' for batch date '||batchDate;

        P_SUCCESS_FLAG     := V_SUCCESS_FLAG;
        P_MESSAGE          := V_MESSAGE;

        DBMS_OUTPUT.PUT_LINE('UPD_INFAR006_ZERO_BAL : V_SUCCESS_FLAG = '||V_SUCCESS_FLAG||' '||V_MESSAGE); 

    EXCEPTION
        WHEN OTHERS THEN 

                V_SUCCESS_FLAG     := c_NO;
                V_MESSAGE          := 'Failure occured in UPD_INFAR006_ZERO_BAL :' ||SQLERRM;

                P_SUCCESS_FLAG     := V_SUCCESS_FLAG;
                P_MESSAGE          := V_MESSAGE;

				LOG_CARS_ERROR(
					p_errorLevel    => '3',
					p_severity      => c_HIGH_SEVERITY,
					p_errorDetail   => 'FISCAL UPD_INFAR006_ZERO_BAL procedure did not succeed',
					p_errorCode     => '5000',
					p_errorMessage  => V_MESSAGE ,
					p_dataSource    => c_CARS_DB
    				);  

                DBMS_OUTPUT.PUT_LINE(' V_SUCCESS_FLAG = '||V_SUCCESS_FLAG||' '||V_MESSAGE );
                
    END UPD_INFAR006_ZERO_BAL;
    
    PROCEDURE GET_INFAR006_DATA (
        P_BATCH_ID              INFAR006_OUTBOUND.BATCH_ID%TYPE,
        P_BATCH_DATE            BATCH.BATCH_DATE%TYPE,
        P_PROGRAM_UNIT          PROGRAM_UNIT.PROGRAM_UNIT_CODE%TYPE,    
        P_TRANSACTION_CODE      ACCOUNTING_ENTRY_TYPE.ACCTG_TRANSACT_CODE%TYPE,
        P_EVENT_TYPE_CODE       VARCHAR2, 
        P_LAST_BATCH_DATE       DATE,
        P_SUCCESS_FLAG      OUT VARCHAR2,
        P_MESSAGE           OUT VARCHAR2
        ) AS
        
       V_CUST_ID                            INFAR006_OUTBOUND.CUST_ID%TYPE;
       V_ITEM                               INFAR006_OUTBOUND.ITEM%TYPE; 
       V_ITEM_LINE                          INFAR006_OUTBOUND.ITEM_LINE%TYPE;
       V_ENTRY_TYPE                         INFAR006_OUTBOUND.ENTRY_TYPE%TYPE;
       V_ENTRY_REASON                       INFAR006_OUTBOUND.ENTRY_REASON%TYPE;
       V_ENTRY_AMT                          INFAR006_OUTBOUND.ENTRY_AMT%TYPE;
       V_ASOF_DT                            INFAR006_OUTBOUND.ASOF_DT%TYPE;
       V_PYMNT_TERMS_CD                     INFAR006_OUTBOUND.PYMNT_TERMS_CD%TYPE;               
       V_ADDRESS_SEQ_NUM                    INFAR006_OUTBOUND.ADDRESS_SEQ_NUM%TYPE;
       V_ALTACCT                            INFAR006_OUTBOUND.ALTACCT%TYPE; 
       V_DEPTID                             INFAR006_OUTBOUND.DEPTID%TYPE;
       V_PRODUCT                            INFAR006_OUTBOUND.PRODUCT%TYPE;
       V_FUND_CODE                          INFAR006_OUTBOUND.FUND_CODE%TYPE ;
       V_A_DST_SEQ_NUM                      INFAR006_OUTBOUND.DST_SEQ_NUM%TYPE;
       V_A_SYSTEM_DEFINED                   INFAR006_OUTBOUND.SYSTEM_DEFINED%TYPE;
       V_U_DST_SEQ_NUM                      INFAR006_OUTBOUND.DST_SEQ_NUM%TYPE;
       V_U_SYSTEM_DEFINED                   INFAR006_OUTBOUND.SYSTEM_DEFINED%TYPE;   
       V_DEBIT_MONETARY_AMOUNT              INFAR006_OUTBOUND.MONETARY_AMOUNT%TYPE;
       V_CREDIT_MONETARY_AMOUNT             INFAR006_OUTBOUND.MONETARY_AMOUNT%TYPE;
       V_A_ACCOUNT                          INFAR006_OUTBOUND.ACCOUNT%TYPE;
       V_U_ACCOUNT                          INFAR006_OUTBOUND.ACCOUNT%TYPE;
       V_ACCTG_ENTRY_ID                     INFAR006_OUTBOUND.ACCTG_ENTRY_ID%TYPE;
       V_ACCOUNTING_DT                      INFAR006_OUTBOUND.ACCOUNTING_DT%TYPE;
       V_CONTROL_AMT                        INFAR006_OUTBOUND.CONTROL_AMT%TYPE;
       V_CONTROL_CNT                        INFAR006_OUTBOUND.CONTROL_CNT%TYPE;
       V_GROUP_ID_STG                       INFAR006_OUTBOUND.GROUP_ID_STG%TYPE;
       V_GROUP_SEQ_NUM                      INFAR006_OUTBOUND.GROUP_SEQ_NUM%TYPE;
       V_FUND                               FUND.FUND%TYPE;
       V_FUND_DETAIL                        FUND.FUND_DETAIL%TYPE;
       V_CHARTFIELD1                        INFAR006_OUTBOUND.CHARTFIELD1%TYPE := NULL;
       V_AR_ROOT_DOCUMENT                   EVENT.AR_ROOT_DOCUMENT%TYPE; 
       V_EVENT_DATE                         EVENT.EVENT_DATE%TYPE;
       V_EVENT_TYPE_CODE                    EVENT_TYPE.EVENT_TYPE_CODE%TYPE;      
       V_PRIOR_FISCAL_YEAR                  INFAR006_OUTBOUND.PRODUCT%TYPE;
       V_FS_PROCESS_DATE                    ACCOUNTING_ENTRY_STATUS.FS_PROCESS_DATE%TYPE;
       V_SUCCESS_FLAG                       VARCHAR2(1)     := c_NO;
       V_MESSAGE                            VARCHAR2(500);
             
       -- 5/24/2018, Vinay Patil: Cursor parameter removed instead used the Program Unit procedure Parameter as filter and function parameter
       CURSOR infar006Data_Cursor IS
         SELECT 
           EVENT.AR_ROOT_DOCUMENT ,
           EVENT.EVENT_DATE ,
           EVENT_TYPE.EVENT_TYPE_CODE,
           FS_INTERFACE_PKG.GET_FS_LINE_NUMBER(EVENT.AR_ROOT_DOCUMENT, P_PROGRAM_UNIT)   AS FS_LINE_NUMBER,
           FS_INTERFACE_PKG.GET_FS_ITEM_LINE(EVENT.AR_ROOT_DOCUMENT, ACCOUNTING_ENTRY_TYPE.ACCTG_TRANSACT_CODE,P_PROGRAM_UNIT) AS FS_ITEM_LINE,          
           FS_ENTRY_TYPE.ENTRY_TYPE_CODE,
           FS_ENTRY_REASON_TYPE.ENTRY_REASON_CODE,

           CASE
                WHEN (FS_ENTRY_TYPE.ENTRY_TYPE_CODE IN (c_DR,c_DRYEC)) THEN 
                    ACCOUNTING_ENTRY.AMOUNT

                WHEN (FS_ENTRY_TYPE.ENTRY_TYPE_CODE IN (c_CR,c_CRYEC,c_WO))  THEN 
                    ACCOUNTING_ENTRY.AMOUNT * -1
           END  as "AMOUNT",       
           
           FS_INTERFACE_PKG.GET_FS_DIR_PAYMENT_TERMS(P_PROGRAM_UNIT),

           CASE
                WHEN (FS_ENTRY_TYPE.ENTRY_TYPE_CODE IN (c_DR,c_DRYEC)) THEN
                    FS_INTERFACE_PKG.GET_FS_DEBIT_AMOUNT(ACCOUNTING_ENTRY.ACCTG_ENTRY_ID)

                WHEN (FS_ENTRY_TYPE.ENTRY_TYPE_CODE IN (c_CR,c_CRYEC,c_WO)) THEN
                    FS_INTERFACE_PKG.GET_FS_CREDIT_AMOUNT(ACCOUNTING_ENTRY.ACCTG_ENTRY_ID)
           
            END   as "A",

            CASE
                WHEN (FS_ENTRY_TYPE.ENTRY_TYPE_CODE IN (c_DR,c_DRYEC)) THEN
                    FS_INTERFACE_PKG.GET_FS_CREDIT_AMOUNT(ACCOUNTING_ENTRY.ACCTG_ENTRY_ID)

                WHEN (FS_ENTRY_TYPE.ENTRY_TYPE_CODE IN (c_CR,c_CRYEC,c_WO)) THEN
                    FS_INTERFACE_PKG.GET_FS_DEBIT_AMOUNT(ACCOUNTING_ENTRY.ACCTG_ENTRY_ID)
            END as "U",

           FS_INTERFACE_PKG.GET_FS_GL_REV_SRC(ACCOUNTING_ENTRY.ACCTG_ENTRY_ID, 
                                             V_A_SYSTEM_DEFINED, 
                                             FS_ENTRY_TYPE.ENTRY_TYPE_CODE, 
                                             ACCOUNTING_ENTRY_TYPE.ACCTG_TRANSACT_CODE), -- A

           FS_INTERFACE_PKG.GET_FS_GL_REV_SRC(ACCOUNTING_ENTRY.ACCTG_ENTRY_ID, 
                                            V_U_SYSTEM_DEFINED, 
                                            FS_ENTRY_TYPE.ENTRY_TYPE_CODE, 
                                            ACCOUNTING_ENTRY_TYPE.ACCTG_TRANSACT_CODE),  -- U

           FS_INTERFACE_PKG.GET_FS_ALT_ACCT(ACCOUNTING_CODE.REVENUE_SOURCE_CODE, 
                                            ACCOUNTING_CODE.AGENCY_SOURCE_CODE, 
                                            ACCOUNTING_ENTRY_TYPE.ACCTG_TRANSACT_CODE) AS FS_ALT_ACCT, 

           c_FS_DIR_BIZ_UNIT|| ACCOUNTING_CODE.INDEX_CODE AS INDEX_CODE,
           FUND.FUND,
           FUND.FUND_DETAIL,
           ACCOUNTING_ENTRY.ACCTG_ENTRY_ID
         FROM ACCOUNTING_TRANSACTION
             INNER JOIN ACCOUNTING_ENTRY
                 ON (ACCOUNTING_TRANSACTION.ACCTG_TRANSACTION_ID    =   ACCOUNTING_ENTRY.ACCTG_TRANSACTION_ID)
             INNER JOIN ACCOUNTING_ENTRY_STATUS
                 ON (ACCOUNTING_ENTRY_STATUS.ACCTG_ENTRY_ID         =   ACCOUNTING_ENTRY.ACCTG_ENTRY_ID)                                                                             
             INNER JOIN ACCOUNTING_ENTRY_TYPE
                 ON (ACCOUNTING_ENTRY.ACCTG_ENTRY_TYPE_ID           =   ACCOUNTING_ENTRY_TYPE.ACCTG_ENTRY_TYPE_ID)                                        
             INNER JOIN FS_ENTRY_REASON_TYPE
                 ON (FS_ENTRY_REASON_TYPE.ENTRY_REASON_ID           =   ACCOUNTING_ENTRY.ENTRY_REASON_ID)
             INNER JOIN FS_ENTRY_TYPE
                 ON (FS_ENTRY_TYPE.ENTRY_TYPE_ID                    =   FS_ENTRY_REASON_TYPE.ENTRY_TYPE_ID)                                                                        
             INNER JOIN ACCTG_TRANSACT_EVENT_ASSOC
                 ON (ACCOUNTING_TRANSACTION.ACCTG_TRANSACTION_ID    =   ACCTG_TRANSACT_EVENT_ASSOC.ACCTG_TRANSACTION_ID)                     
             INNER JOIN ACCOUNTING_CODE
                 ON (ACCOUNTING_CODE.ACCOUNTING_CODE_ID             =   ACCOUNTING_ENTRY.ACCOUNTING_CODE_ID) 
             INNER JOIN FUND_ALLOCATION
                 ON (FUND_ALLOCATION.FUND_ALLOCATION_ID             =   ACCOUNTING_CODE.FUND_ALLOCATION_ID)  
             INNER JOIN FUND ON (FUND.FUND_ID                       =   FUND_ALLOCATION.FUND_TO_ID)                         
             INNER JOIN EVENT
                  ON (EVENT.EVENT_ID                                =   ACCTG_TRANSACT_EVENT_ASSOC.EVENT_ID) 
             INNER JOIN EVENT_TYPE
                  ON (EVENT_TYPE.EVENT_TYPE_ID = EVENT.EVENT_TYPE_ID) 
             WHERE ACCOUNTING_ENTRY_STATUS.FS_PROCESS_STATUS        =   c_STATUS_SELECTED
               AND TRUNC(ACCOUNTING_ENTRY_STATUS.FS_PROCESS_DATE)   =   TRUNC(V_ACCOUNTING_DT)
               AND EVENT_TYPE.PROGRAM_UNIT_CODE                     =   P_PROGRAM_UNIT
                
                -- 5/24/2018, Vinay Patil: This is removed as the zero balance invoices status are already marked as NOT_TRANSMITTED
                -- 7/13/2018, CARS Team: aded this back in case records slip through for $0 events
                AND ACCOUNTING_ENTRY.AMOUNT <> 0;            
    BEGIN
        DBMS_OUTPUT.PUT_LINE('**** Begin GET_INFAR006_DATA ****');
        SELECT TO_DATE(TO_CHAR(TO_DATE(P_BATCH_DATE, 'YYYYMMDD'), 'MMDDYYYY'), 'MM/DD/YYYY') INTO V_ACCOUNTING_DT FROM DUAL; 
        
        SELECT SYSDATE INTO V_FS_PROCESS_DATE FROM DUAL; 
        
        -- Change Status to SELECTED in Accounting Entry Status
        UPDATE_ACCTG_ENTRY_STATUS(c_STATUS_SELECTED, V_FS_PROCESS_DATE, P_PROGRAM_UNIT, P_TRANSACTION_CODE, P_EVENT_TYPE_CODE, P_LAST_BATCH_DATE, c_STATUS_NEW);
              
        V_A_SYSTEM_DEFINED := GET_FS_SYSTEM_DEFINED('AR Line');
        V_U_SYSTEM_DEFINED := GET_FS_SYSTEM_DEFINED('Offsetting Line');
                
        V_A_DST_SEQ_NUM := c_A_DST_SEQ_NUM; --100;
        V_U_DST_SEQ_NUM := c_U_DST_SEQ_NUM; --1;
        
        DBMS_OUTPUT.PUT_LINE('Accounting Date: ' || V_ACCOUNTING_DT     
                                ||' A Distribution Sequence Number: ' || V_A_DST_SEQ_NUM ||' A System Define: ' || V_A_SYSTEM_DEFINED  
                                ||' U Distribution Sequence Number: ' || V_U_DST_SEQ_NUM ||' U System Define: ' || V_U_SYSTEM_DEFINED);
    
        
        -- 5/24/2018, Vinay Patil: Cursor Parameters are not needed.Added variables for AR_ROOT_DOCUMENT, EVENT_DATE and EVENT_TYPE_CODE
        OPEN infar006Data_Cursor;
        LOOP
            FETCH infar006Data_Cursor INTO  V_AR_ROOT_DOCUMENT, 
                                            V_EVENT_DATE ,      
                                            V_EVENT_TYPE_CODE,
                                            V_ITEM,             
                                            V_ITEM_LINE, 
                                            V_ENTRY_TYPE,       
                                            V_ENTRY_REASON,     
                                            V_ENTRY_AMT, 
                                            V_PYMNT_TERMS_CD,   
                                            V_DEBIT_MONETARY_AMOUNT,           
                                            V_CREDIT_MONETARY_AMOUNT,
                                            V_A_ACCOUNT,        
                                            V_U_ACCOUNT,        
                                            V_ALTACCT, 
                                            V_DEPTID,           
                                            V_FUND_CODE, 
                                            V_FUND_DETAIL,      
                                            V_ACCTG_ENTRY_ID;
            EXIT WHEN infar006Data_Cursor%NOTFOUND; 
            
            --5/24/2018, Vinay Patil: Call the Procedure to fetch Customer Id, Address Sequence Number, AS OF Date and FISCAL Year
            FS_AR_SETUP_DATA(
                P_AR_ROOT_DOCUMENT  => V_AR_ROOT_DOCUMENT,
                P_CUR_EVENT_DATE    => V_EVENT_DATE, 
                P_EVENT_TYPE_CODE   => V_EVENT_TYPE_CODE,
                P_PROGRAM_UNIT      => P_PROGRAM_UNIT, 
                P_CUST_ID           => V_CUST_ID,
                P_ADDRESS_SEQ_NUM   => V_ADDRESS_SEQ_NUM,
                P_AS_OF_DATE        => V_ASOF_DT,
                P_FISCAL_YEAR       => V_PRODUCT,
                P_PRIOR_FISCAL_YEAR => V_PRIOR_FISCAL_YEAR,
                P_SUCCESS_FLAG      => V_SUCCESS_FLAG,
                P_MESSAGE           => V_MESSAGE
                );
            
            DBMS_OUTPUT.PUT_LINE(
              '**** CutID: '        || V_CUST_ID ||
              ' *Item: '            || V_ITEM || ' *Item Line: ' || V_ITEM_LINE ||
              ' Entry type: '       || V_ENTRY_TYPE ||
              ' *Entry reason: '    || V_ENTRY_REASON ||
              ' *Entry Amount: '    || V_ENTRY_AMT ||
              ' *As Of Date: '      || V_ASOF_DT ||
              ' *Payment Term: '    || V_PYMNT_TERMS_CD ||
              ' *Address ID: '      || V_ADDRESS_SEQ_NUM ||
              ' *A Amount: '        || V_DEBIT_MONETARY_AMOUNT ||
              ' *U Amount: '        || V_CREDIT_MONETARY_AMOUNT ||
              ' *A Account: '       || V_A_ACCOUNT ||
              ' *U Account: '       || V_U_ACCOUNT ||
              ' *Alternate Account: ' || V_ALTACCT ||
              ' *Department ID: '   || V_DEPTID ||
              ' *Product: '         || V_PRODUCT ||
              ' *Fund: '            || V_FUND_CODE ||    
              ' *Fund Detail: '     || V_FUND_DETAIL ||
              ' *Account Entry ID: '|| V_ACCTG_ENTRY_ID);

            -- Check Item Line. If Line Item is -1, then skip insert data
            -- because it has invalid AR Root Format for SIMS and PVERA
            IF (V_ITEM_LINE = -1) THEN
            
                UPDATE_STATUS_BY_ID(c_STATUS_FAILED, V_ACCOUNTING_DT, V_ACCTG_ENTRY_ID);
                                
            ELSIF (V_CUST_ID IS NULL OR V_ADDRESS_SEQ_NUM IS NULL) THEN
                
                -- Update Accounting Entry Status to FAILED status
                UPDATE_STATUS_BY_ID(c_STATUS_FAILED, V_ACCOUNTING_DT, V_ACCTG_ENTRY_ID);
                
            ELSE
                -- Add Entry Amount into GET_INFAR006_COUNTER_DATA
                GET_INFAR006_COUNTER_DATA(P_BATCH_ID, P_PROGRAM_UNIT, NULL, V_ENTRY_AMT, c_ADD_COUNTER, V_SUCCESS_FLAG, V_MESSAGE); 
                
                V_GROUP_SEQ_NUM := FS_INTERFACE_PKG.V_INFAR006_COUNT_REC.GROUP_SEQ_NUM;  
                V_GROUP_ID_STG  := FS_INTERFACE_PKG.V_INFAR006_COUNT_REC.GROUP_ID_STG;
                V_CONTROL_AMT   := FS_INTERFACE_PKG.V_INFAR006_COUNT_REC.CONTROL_AMT;
                V_CONTROL_CNT   := FS_INTERFACE_PKG.V_INFAR006_COUNT_REC.CONTROL_CNT;   
                
                --Chartfield 1 only if fund detail is not null
                IF (V_FUND_DETAIL IS NOT NULL) THEN
                    V_CHARTFIELD1 := V_FUND_CODE || V_FUND_DETAIL;
                END IF;

                -- Call INSERT_INFAR006_DATA for A Account
                INSERT_INFAR006_DATA(
                        P_BATCH_ID,         P_PROGRAM_UNIT,         V_ACCOUNTING_DT,        V_CUST_ID,
                        V_ITEM,             V_ITEM_LINE,            V_ENTRY_TYPE,           V_ENTRY_REASON,            
                        V_ENTRY_AMT,        V_ASOF_DT,              V_PYMNT_TERMS_CD,       V_ADDRESS_SEQ_NUM,             
                        V_A_DST_SEQ_NUM,    V_A_SYSTEM_DEFINED,     V_DEBIT_MONETARY_AMOUNT,V_A_ACCOUNT, 
                        NULL,               V_DEPTID,               V_PRODUCT,              V_FUND_CODE, 
                        V_CONTROL_AMT,      V_CONTROL_CNT,          V_GROUP_ID_STG,         V_GROUP_SEQ_NUM, 
                        V_ACCTG_ENTRY_ID,   V_CHARTFIELD1,          V_SUCCESS_FLAG,         V_MESSAGE);
            
                -- Call INSERT_INFAR006_DATA for U Account
                INSERT_INFAR006_DATA(
                        P_BATCH_ID,     P_PROGRAM_UNIT,     V_ACCOUNTING_DT,    V_CUST_ID,
                        V_ITEM,         V_ITEM_LINE,        V_ENTRY_TYPE,       V_ENTRY_REASON,            
                        V_ENTRY_AMT,    V_ASOF_DT,          V_PYMNT_TERMS_CD,   V_ADDRESS_SEQ_NUM,             
                        V_U_DST_SEQ_NUM,V_U_SYSTEM_DEFINED, V_CREDIT_MONETARY_AMOUNT, 
                        V_U_ACCOUNT,    V_ALTACCT,          V_DEPTID,           V_PRODUCT,
                        V_FUND_CODE,    V_CONTROL_AMT,      V_CONTROL_CNT,      V_GROUP_ID_STG,
                        V_GROUP_SEQ_NUM,V_ACCTG_ENTRY_ID,   V_CHARTFIELD1,      V_SUCCESS_FLAG, 
                        V_MESSAGE);
                    
                --This is to empty the group bu counter since accounting has each transaction in its own group number
                GET_INFAR006_COUNTER_DATA( P_BATCH_ID, P_PROGRAM_UNIT, NULL, 0, c_EMPTY_COUNTER, V_SUCCESS_FLAG, V_MESSAGE);
              
            END IF;
                                                          
        END LOOP;
    
        CLOSE infar006Data_Cursor; 
        
        P_SUCCESS_FLAG     := V_SUCCESS_FLAG;
        P_MESSAGE          := V_MESSAGE;
        
    EXCEPTION
        WHEN OTHERS THEN
            --Handle Error
            DBMS_OUTPUT.PUT_LINE('Failed to Get INFAR006 Data'); 
            V_SUCCESS_FLAG     := c_NO;
            V_MESSAGE          := 'Failure occured in GET_INFAR006_DATA :' ||SQLERRM;

            P_SUCCESS_FLAG     := V_SUCCESS_FLAG;
            P_MESSAGE          := V_MESSAGE;

            LOG_CARS_ERROR(
                p_errorLevel    => '3',
                p_severity      => c_HIGH_SEVERITY,
                p_errorDetail   => 'FISCAL GET_INFAR006_DATA procedure did not succeed',
                p_errorCode     => '5000',
                p_errorMessage  => V_MESSAGE ,
                p_dataSource    => c_CARS_DB
				);  
                DBMS_OUTPUT.PUT_LINE(' V_SUCCESS_FLAG = '||V_SUCCESS_FLAG||' '||V_MESSAGE );
                
    END GET_INFAR006_DATA;
    
    PROCEDURE INSERT_INFAR006_DATA (
            P_BATCH_ID              INFAR006_OUTBOUND.BATCH_ID%TYPE,
            P_PROGRAM_UNIT          VARCHAR2,
            P_ACCOUNTING_DT         INFAR006_OUTBOUND.ACCOUNTING_DT%TYPE,
            P_CUST_ID               INFAR006_OUTBOUND.CUST_ID%TYPE,
            P_ITEM                  INFAR006_OUTBOUND.ITEM%TYPE,
            P_ITEM_LINE             INFAR006_OUTBOUND.ITEM_LINE%TYPE,
            P_ENTRY_TYPE            INFAR006_OUTBOUND.ENTRY_TYPE%TYPE,    
            P_ENTRY_REASON          INFAR006_OUTBOUND.ENTRY_REASON%TYPE,
            P_ENTRY_AMT             INFAR006_OUTBOUND.ENTRY_AMT%TYPE, 
            P_ASOF_DT               INFAR006_OUTBOUND.ASOF_DT%TYPE,
            P_PYMNT_TERMS_CD        INFAR006_OUTBOUND.PYMNT_TERMS_CD%TYPE,
            P_ADDRESS_SEQ_NUM       INFAR006_OUTBOUND.ADDRESS_SEQ_NUM%TYPE,             
            P_DST_SEQ_NUM           INFAR006_OUTBOUND.DST_SEQ_NUM%TYPE,
            P_SYSTEM_DEFINED        INFAR006_OUTBOUND.SYSTEM_DEFINED%TYPE, 
            P_MONETARY_AMOUNT       INFAR006_OUTBOUND.MONETARY_AMOUNT%TYPE,
            P_ACCOUNT               INFAR006_OUTBOUND.ACCOUNT%TYPE,
            P_ALTACCT               INFAR006_OUTBOUND.ALTACCT%TYPE,
            P_DEPTID                INFAR006_OUTBOUND.DEPTID%TYPE,
            P_PRODUCT               INFAR006_OUTBOUND.PRODUCT%TYPE,
            P_FUND_CODE             INFAR006_OUTBOUND.FUND_CODE%TYPE,
            P_CONTROL_AMT           INFAR006_OUTBOUND.CONTROL_AMT%TYPE,
            P_CONTROL_CNT           INFAR006_OUTBOUND.CONTROL_CNT%TYPE,
            P_GROUP_ID_STG          INFAR006_OUTBOUND.GROUP_ID_STG%TYPE,
            P_GROUP_SEQ_NUM         INFAR006_OUTBOUND.GROUP_SEQ_NUM%TYPE,            
            P_ACCTG_ENTRY_ID        NUMBER, 
            P_CHARTFIELD1           INFAR006_OUTBOUND.CHARTFIELD1%TYPE,
            P_SUCCESS_FLAG     OUT VARCHAR2,
            P_MESSAGE          OUT VARCHAR2
            ) AS
       V_BATCH_ID                           INFAR006_OUTBOUND.BATCH_ID%TYPE             := P_BATCH_ID;
       V_INFAR006_OUTBOUND_ID               INFAR006_OUTBOUND.INFAR006_OUTBOUND_ID%TYPE := NULL;
       V_GROUP_BU                           INFAR006_OUTBOUND.GROUP_BU%TYPE             := c_FS_DIR_BIZ_UNIT;
       V_GROUP_ID_STG                       INFAR006_OUTBOUND.GROUP_ID_STG%TYPE         := P_GROUP_ID_STG;
       V_ACCOUNTING_DT                      INFAR006_OUTBOUND.ACCOUNTING_DT%TYPE        := P_ACCOUNTING_DT;
       V_GROUP_TYPE                         INFAR006_OUTBOUND.GROUP_TYPE%TYPE           := c_GROUP_TYPE;
       V_CONTROL_AMT                        INFAR006_OUTBOUND.CONTROL_AMT%TYPE          := P_CONTROL_AMT;
       V_CONTROL_CNT                        INFAR006_OUTBOUND.CONTROL_CNT%TYPE          := P_CONTROL_CNT;
       V_POST_ACTION                        INFAR006_OUTBOUND.POST_ACTION%TYPE          := c_POST_ACTION;
       V_GROUP_SEQ_NUM                      INFAR006_OUTBOUND.GROUP_SEQ_NUM%TYPE        := P_GROUP_SEQ_NUM;
       V_CUST_ID                            INFAR006_OUTBOUND.CUST_ID%TYPE              := P_CUST_ID;
       V_ITEM                               INFAR006_OUTBOUND.ITEM%TYPE                 := P_ITEM;
       V_ITEM_LINE                          INFAR006_OUTBOUND.ITEM_LINE%TYPE            := P_ITEM_LINE;           
       V_ENTRY_TYPE                         INFAR006_OUTBOUND.ENTRY_TYPE%TYPE           := P_ENTRY_TYPE;
       V_ENTRY_REASON                       INFAR006_OUTBOUND.ENTRY_REASON%TYPE         := P_ENTRY_REASON;
       V_ENTRY_AMT                          INFAR006_OUTBOUND.ENTRY_AMT%TYPE            := P_ENTRY_AMT;
       V_ASOF_DT                            INFAR006_OUTBOUND.ASOF_DT%TYPE              := P_ASOF_DT;
       V_PYMNT_TERMS_CD                     INFAR006_OUTBOUND.PYMNT_TERMS_CD%TYPE       := P_PYMNT_TERMS_CD;
       V_DUE_DT                             INFAR006_OUTBOUND.DUE_DT%TYPE               := NULL;
       V_CR_ANALYST                         INFAR006_OUTBOUND.CR_ANALYST%TYPE           := NULL;
       V_COLLECTOR                          INFAR006_OUTBOUND.COLLECTOR%TYPE            := NULL;
       V_PO_REF                             INFAR006_OUTBOUND.PO_REF%TYPE               := NULL;
       V_DOCUMENT                           INFAR006_OUTBOUND.DOCUMENT%TYPE             := NULL;
       V_CONTRACT_NUM                       INFAR006_OUTBOUND.CONTRACT_NUM%TYPE         := NULL;
       V_DISPUTE_CHKBOX                     INFAR006_OUTBOUND.DISPUTE_CHKBOX%TYPE       := c_NO;
       V_DISPUTE_STATUS                     INFAR006_OUTBOUND.DISPUTE_STATUS%TYPE       := NULL;
       V_DISPUTE_DATE                       INFAR006_OUTBOUND.DISPUTE_DATE%TYPE         := NULL;
       V_DISPUTE_AMOUNT                     INFAR006_OUTBOUND.DISPUTE_AMOUNT%TYPE       := NULL;
       V_COLLECTION_CHKBOX                  INFAR006_OUTBOUND.COLLECTION_CHKBOX%TYPE    := c_NO;
       V_COLLECTION_STATUS                  INFAR006_OUTBOUND.COLLECTION_STATUS%TYPE    := NULL;
       V_COLLECTION_DT                      INFAR006_OUTBOUND.COLLECTION_DT%TYPE        := NULL;
       V_ADDRESS_SEQ_NUM                    INFAR006_OUTBOUND.ADDRESS_SEQ_NUM%TYPE      := P_ADDRESS_SEQ_NUM;
       V_USER_DT1                           INFAR006_OUTBOUND.USER_DT1%TYPE             := NULL;
       V_USER_DT2                           INFAR006_OUTBOUND.USER_DT2%TYPE             := NULL;
       V_USER_DT3                           INFAR006_OUTBOUND.USER_DT3%TYPE             := NULL;
       V_USER_DT4                           INFAR006_OUTBOUND.USER_DT4%TYPE             := NULL;
       V_DST_SEQ_NUM                        INFAR006_OUTBOUND.DST_SEQ_NUM%TYPE          := P_DST_SEQ_NUM;
       V_SYSTEM_DEFINED                     INFAR006_OUTBOUND.SYSTEM_DEFINED%TYPE       := P_SYSTEM_DEFINED;
       V_MONETARY_AMOUNT                    INFAR006_OUTBOUND.MONETARY_AMOUNT%TYPE      := P_MONETARY_AMOUNT;
       V_BUSINESS_UNIT_GL                   INFAR006_OUTBOUND.BUSINESS_UNIT_GL%TYPE     := c_FS_DIR_BIZ_UNIT;
       V_ACCOUNT                            INFAR006_OUTBOUND.ACCOUNT%TYPE              := P_ACCOUNT; -- GENERAL LEDGER NUMBER
       V_ALTACCT                            INFAR006_OUTBOUND.ALTACCT%TYPE              := P_ALTACCT; -- REVENUE SOURCE CODE
       V_DEPTID                             INFAR006_OUTBOUND.DEPTID%TYPE               := P_DEPTID;  -- 7350 PLUS INDEX CODE
       V_OPERATING_UNIT                     INFAR006_OUTBOUND.OPERATING_UNIT%TYPE       := NULL;
       V_PRODUCT                            INFAR006_OUTBOUND.PRODUCT%TYPE              := P_PRODUCT;
       V_FUND_CODE                          INFAR006_OUTBOUND.FUND_CODE%TYPE            := P_FUND_CODE;
       V_CLASS_FLD                          INFAR006_OUTBOUND.CLASS_FLD%TYPE            := NULL;
       V_PROGRAM_CODE                       INFAR006_OUTBOUND.PROGRAM_CODE%TYPE         := NULL;
       V_BUDGET_REF                         INFAR006_OUTBOUND.BUDGET_REF%TYPE           := NULL;
       V_AFFILIATE                          INFAR006_OUTBOUND.AFFILIATE%TYPE            := NULL;
       V_AFFILIATE_INTRA1                   INFAR006_OUTBOUND.AFFILIATE_INTRA1%TYPE     := NULL;
       V_AFFILIATE_INTRA2                   INFAR006_OUTBOUND.AFFILIATE_INTRA2%TYPE     := NULL;
       V_CHARTFIELD1                        INFAR006_OUTBOUND.CHARTFIELD1%TYPE          := P_CHARTFIELD1;  -- DIR BUSINESS FUND PLUS FUND_DETAIL
       V_CHARTFIELD2                        INFAR006_OUTBOUND.CHARTFIELD2%TYPE          := NULL;
       V_CHARTFIELD3                        INFAR006_OUTBOUND.CHARTFIELD3%TYPE          := NULL;
       V_BUSINESS_UNIT_PC                   INFAR006_OUTBOUND.BUSINESS_UNIT_PC%TYPE     := NULL;
       V_PROJECT_ID                         INFAR006_OUTBOUND.PROJECT_ID%TYPE           := NULL;
       V_ACTIVITY_ID                        INFAR006_OUTBOUND.ACTIVITY_ID%TYPE          := NULL;
       V_RESOURCE_TYPE                      INFAR006_OUTBOUND.RESOURCE_TYPE%TYPE        := NULL;
       V_RESOURCE_CATEGORY                  INFAR006_OUTBOUND.RESOURCE_CATEGORY%TYPE    := NULL;
       V_RESOURCE_SUB_CAT                   INFAR006_OUTBOUND.RESOURCE_SUB_CAT%TYPE     := NULL;
       V_ANALYSIS_TYPE                      INFAR006_OUTBOUND.ANALYSIS_TYPE%TYPE        := NULL;
       V_ZZ_FUND                            INFAR006_OUTBOUND.ZZ_FUND%TYPE              := NULL;
       V_ZZ_SUB_FUND                        INFAR006_OUTBOUND.ZZ_SUB_FUND%TYPE          := NULL;
       V_ZZ_PROGRAM                         INFAR006_OUTBOUND.ZZ_PROGRAM%TYPE           := NULL;
       V_ZZ_ELEMENT                         INFAR006_OUTBOUND.ZZ_ELEMENT%TYPE           := NULL;
       V_ZZ_COMPONENT                       INFAR006_OUTBOUND.ZZ_COMPONENT%TYPE         := NULL;
       V_ZZ_TASK                            INFAR006_OUTBOUND.ZZ_TASK%TYPE              := NULL;
       V_ZZ_PROG_COST_ACCT                  INFAR006_OUTBOUND.ZZ_PROG_COST_ACCT%TYPE    := NULL;
       V_ZZ_ORG_CODE                        INFAR006_OUTBOUND.ZZ_ORG_CODE%TYPE          := NULL;
       V_ZZ_INT_STRUCT1                     INFAR006_OUTBOUND.ZZ_INT_STRUCT1%TYPE       := NULL;
       V_ZZ_INT_STRUCT2                     INFAR006_OUTBOUND.ZZ_INT_STRUCT2%TYPE       := NULL;
       V_ZZ_INT_STRUCT3                     INFAR006_OUTBOUND.ZZ_INT_STRUCT3%TYPE       := NULL;
       V_ZZ_INT_STRUCT4                     INFAR006_OUTBOUND.ZZ_INT_STRUCT4%TYPE       := NULL;
       V_ZZ_INT_STRUCT5                     INFAR006_OUTBOUND.ZZ_INT_STRUCT5%TYPE       := NULL;
       V_ZZ_INDEX                           INFAR006_OUTBOUND.ZZ_INDEX%TYPE             := NULL;
       V_ZZ_OBJ_DETAIL                      INFAR006_OUTBOUND.ZZ_OBJ_DETAIL%TYPE        := NULL;
       V_ZZ_AGNCY_OBJ                       INFAR006_OUTBOUND.ZZ_AGNCY_OBJ%TYPE         := NULL;
       V_ZZ_SOURCE                          INFAR006_OUTBOUND.ZZ_SOURCE%TYPE            := NULL;
       V_ZZ_AGNCY_SRC                       INFAR006_OUTBOUND.ZZ_AGNCY_SRC%TYPE         := NULL;
       V_ZZ_GL_ACCOUNT                      INFAR006_OUTBOUND.ZZ_GL_ACCOUNT%TYPE        := NULL;
       V_ZZ_SUBSIDIARY                      INFAR006_OUTBOUND.ZZ_SUBSIDIARY%TYPE        := NULL;
       V_ZZ_FUND_SRC                        INFAR006_OUTBOUND.ZZ_FUND_SRC%TYPE          := NULL;
       V_ZZ_CHARACTER                       INFAR006_OUTBOUND.ZZ_CHARACTER%TYPE         := NULL;
       V_ZZ_METHOD                          INFAR006_OUTBOUND.ZZ_METHOD%TYPE            := NULL;
       V_ZZ_ENACTMENT_YEAR                  INFAR006_OUTBOUND.ZZ_ENACTMENT_YEAR%TYPE    := NULL;
       V_ZZ_REFERENCE                       INFAR006_OUTBOUND.ZZ_REFERENCE%TYPE         := NULL;
       V_ZZ_FISCAL_YEAR                     INFAR006_OUTBOUND.ZZ_FISCAL_YEAR%TYPE       := NULL;
       V_ZZ_APPROP_SYMB                     INFAR006_OUTBOUND.ZZ_APPROP_SYMB%TYPE       := NULL;
       V_ZZ_PROJECT                         INFAR006_OUTBOUND.ZZ_PROJECT%TYPE           := NULL;
       V_ZZ_WORK_PHASE                      INFAR006_OUTBOUND.ZZ_WORK_PHASE%TYPE        := NULL;
       V_ZZ_MULTIPURPOSE                    INFAR006_OUTBOUND.ZZ_MULTIPURPOSE%TYPE      := NULL;
       V_ZZ_LOCATION                        INFAR006_OUTBOUND.ZZ_LOCATION%TYPE          := NULL;
       V_ZZ_DEPT_USE_1                      INFAR006_OUTBOUND.ZZ_DEPT_USE_1%TYPE        := NULL;
       V_ZZ_DEPT_USE_2                      INFAR006_OUTBOUND.ZZ_DEPT_USE_2%TYPE        := NULL;
       V_BUDGET_DT                          INFAR006_OUTBOUND.BUDGET_DT%TYPE            := NULL;
       V_NOTE_TEXT                          INFAR006_OUTBOUND.NOTE_TEXT%TYPE            := 'FISCAL INFAR006';
       V_STATUS                             INFAR006_OUTBOUND.STATUS%TYPE               := c_STATUS_NEW ;
       V_DATA_SOURCE_CODE                   INFAR006_OUTBOUND.DATA_SOURCE_CODE%TYPE     := c_CARS_DB;
       V_CREATED_BY                         INFAR006_OUTBOUND.CREATED_BY%TYPE           := c_USER;
       V_CREATED_DATE                       INFAR006_OUTBOUND.CREATED_DATE%TYPE         := SYSDATE;
       V_MODIFIED_BY                        INFAR006_OUTBOUND.MODIFIED_BY%TYPE          := NULL;
       V_MODIFIED_DATE                      INFAR006_OUTBOUND.MODIFIED_DATE%TYPE        := NULL;
       V_ACCTG_ENTRY_ID                     INFAR006_OUTBOUND.ACCTG_ENTRY_ID%TYPE       := P_ACCTG_ENTRY_ID;
       V_PROGRAM_UNIT_CODE                  INFAR006_OUTBOUND.PROGRAM_UNIT_CODE%TYPE    := P_PROGRAM_UNIT;

       V_SUCCESS_FLAG                       VARCHAR2(1)                                 := c_NO;
       V_MESSAGE                            VARCHAR2(500);
                   
    BEGIN   
        -- Get INFAR006_OUTBOUND_ID 
        SELECT INFAR006_OUTBOUND_ID_SEQ.nextVal INTO V_INFAR006_OUTBOUND_ID FROM DUAL;
        
        IF (P_PROGRAM_UNIT IN (c_PU_CALOSHA,c_PU_EV,c_PU_PV,c_PU_ART)) THEN
            V_COLLECTOR:= c_COLL_DOSH;
        END IF;
        
        INSERT INTO INFAR006_OUTBOUND
           ( BATCH_ID,
           INFAR006_OUTBOUND_ID,
           GROUP_BU,
           GROUP_ID_STG,
           ACCOUNTING_DT,
           GROUP_TYPE,
           CONTROL_AMT,
           CONTROL_CNT,
           POST_ACTION,
           GROUP_SEQ_NUM,
           CUST_ID,
           ITEM,
           ITEM_LINE,
           ENTRY_TYPE,
           ENTRY_REASON,
           ENTRY_AMT,
           ASOF_DT,
           PYMNT_TERMS_CD,
           DUE_DT,
           CR_ANALYST,
           COLLECTOR,
           PO_REF,
           DOCUMENT,
           CONTRACT_NUM,
           DISPUTE_CHKBOX,
           DISPUTE_STATUS,
           DISPUTE_DATE,
           DISPUTE_AMOUNT,
           COLLECTION_CHKBOX,
           COLLECTION_STATUS,
           COLLECTION_DT,
           ADDRESS_SEQ_NUM,
           USER_DT1,
           USER_DT2,
           USER_DT3,
           USER_DT4,
           DST_SEQ_NUM,
           SYSTEM_DEFINED,
           MONETARY_AMOUNT,
           BUSINESS_UNIT_GL,
           ACCOUNT,
           ALTACCT,
           DEPTID,
           OPERATING_UNIT,
           PRODUCT,
           FUND_CODE,
           CLASS_FLD,
           PROGRAM_CODE,
           BUDGET_REF,
           AFFILIATE,
           AFFILIATE_INTRA1,
           AFFILIATE_INTRA2,
           CHARTFIELD1,
           CHARTFIELD2,
           CHARTFIELD3,
           BUSINESS_UNIT_PC,
           PROJECT_ID,
           ACTIVITY_ID,
           RESOURCE_TYPE,
           RESOURCE_CATEGORY,
           RESOURCE_SUB_CAT,
           ANALYSIS_TYPE,
           ZZ_FUND,
           ZZ_SUB_FUND,
           ZZ_PROGRAM,
           ZZ_ELEMENT,
           ZZ_COMPONENT,
           ZZ_TASK,
           ZZ_PROG_COST_ACCT,
           ZZ_ORG_CODE,
           ZZ_INT_STRUCT1,
           ZZ_INT_STRUCT2,
           ZZ_INT_STRUCT3,
           ZZ_INT_STRUCT4,
           ZZ_INT_STRUCT5,
           ZZ_INDEX,
           ZZ_OBJ_DETAIL,
           ZZ_AGNCY_OBJ,
           ZZ_SOURCE,
           ZZ_AGNCY_SRC,
           ZZ_GL_ACCOUNT,
           ZZ_SUBSIDIARY,
           ZZ_FUND_SRC,
           ZZ_CHARACTER,
           ZZ_METHOD,
           ZZ_ENACTMENT_YEAR,
           ZZ_REFERENCE,
           ZZ_FISCAL_YEAR,
           ZZ_APPROP_SYMB,
           ZZ_PROJECT,
           ZZ_WORK_PHASE,
           ZZ_MULTIPURPOSE,
           ZZ_LOCATION,
           ZZ_DEPT_USE_1,
           ZZ_DEPT_USE_2,
           BUDGET_DT,
           NOTE_TEXT,
           STATUS,
           DATA_SOURCE_CODE,
           CREATED_BY,
           CREATED_DATE,
           MODIFIED_BY,
           MODIFIED_DATE,
           ACCTG_ENTRY_ID,
           PROGRAM_UNIT_CODE
            )
         VALUES 
         (
            V_BATCH_ID,
            INFAR006_OUTBOUND_ID_SEQ.NEXTVAL,
            V_GROUP_BU,
            V_GROUP_ID_STG,
            V_ACCOUNTING_DT,
            V_GROUP_TYPE,
            V_CONTROL_AMT,
            V_CONTROL_CNT,
            V_POST_ACTION,
            V_GROUP_SEQ_NUM,
            V_CUST_ID,
            V_ITEM,
            V_ITEM_LINE,
            V_ENTRY_TYPE,
            V_ENTRY_REASON,
            V_ENTRY_AMT,
            V_ASOF_DT,
            V_PYMNT_TERMS_CD,
            V_DUE_DT,
            V_CR_ANALYST,
            V_COLLECTOR,
            V_PO_REF,
            V_DOCUMENT,
            V_CONTRACT_NUM,
            V_DISPUTE_CHKBOX,
            V_DISPUTE_STATUS,
            V_DISPUTE_DATE,
            V_DISPUTE_AMOUNT,
            V_COLLECTION_CHKBOX,
            V_COLLECTION_STATUS,
            V_COLLECTION_DT,
            V_ADDRESS_SEQ_NUM,
            V_USER_DT1,
            V_USER_DT2,
            V_USER_DT3,
            V_USER_DT4,
            V_DST_SEQ_NUM,
            V_SYSTEM_DEFINED,
            V_MONETARY_AMOUNT,
            V_BUSINESS_UNIT_GL,
            V_ACCOUNT,
            V_ALTACCT,
            V_DEPTID,
            V_OPERATING_UNIT,
            V_PRODUCT,
            V_FUND_CODE,
            V_CLASS_FLD,
            V_PROGRAM_CODE,
            V_BUDGET_REF,
            V_AFFILIATE,
            V_AFFILIATE_INTRA1,
            V_AFFILIATE_INTRA2,
            V_CHARTFIELD1,
            V_CHARTFIELD2,
            V_CHARTFIELD3,
            V_BUSINESS_UNIT_PC,
            V_PROJECT_ID,
            V_ACTIVITY_ID,
            V_RESOURCE_TYPE,
            V_RESOURCE_CATEGORY,
            V_RESOURCE_SUB_CAT,
            V_ANALYSIS_TYPE,
            V_ZZ_FUND,
            V_ZZ_SUB_FUND,
            V_ZZ_PROGRAM,
            V_ZZ_ELEMENT,
            V_ZZ_COMPONENT,
            V_ZZ_TASK,
            V_ZZ_PROG_COST_ACCT,
            V_ZZ_ORG_CODE,
            V_ZZ_INT_STRUCT1,
            V_ZZ_INT_STRUCT2,
            V_ZZ_INT_STRUCT3,
            V_ZZ_INT_STRUCT4,
            V_ZZ_INT_STRUCT5,
            V_ZZ_INDEX,
            V_ZZ_OBJ_DETAIL,
            V_ZZ_AGNCY_OBJ,
            V_ZZ_SOURCE,
            V_ZZ_AGNCY_SRC,
            V_ZZ_GL_ACCOUNT,
            V_ZZ_SUBSIDIARY,
            V_ZZ_FUND_SRC,
            V_ZZ_CHARACTER,
            V_ZZ_METHOD,
            V_ZZ_ENACTMENT_YEAR,
            V_ZZ_REFERENCE,
            V_ZZ_FISCAL_YEAR,
            V_ZZ_APPROP_SYMB,
            V_ZZ_PROJECT,
            V_ZZ_WORK_PHASE,
            V_ZZ_MULTIPURPOSE,
            V_ZZ_LOCATION,
            V_ZZ_DEPT_USE_1,
            V_ZZ_DEPT_USE_2,
            V_BUDGET_DT,
            V_NOTE_TEXT,
            V_STATUS,
            V_DATA_SOURCE_CODE,
            V_CREATED_BY,
            V_CREATED_DATE,
            V_MODIFIED_BY,
            V_MODIFIED_DATE,
            V_ACCTG_ENTRY_ID,
            V_PROGRAM_UNIT_CODE
         );
         
        -- Update Accounting Entry Status to BATCHED status
        UPDATE_STATUS_BY_ID(c_STATUS_BATCHED , P_ACCOUNTING_DT, P_ACCTG_ENTRY_ID);
     
        P_SUCCESS_FLAG     := V_SUCCESS_FLAG;
        P_MESSAGE          := V_MESSAGE;    
        
    EXCEPTION
        WHEN OTHERS THEN
            -- Update Accounting Entry Status to FAILED status
            UPDATE_STATUS_BY_ID(c_STATUS_FAILED, P_ACCOUNTING_DT, P_ACCTG_ENTRY_ID);
                
            V_SUCCESS_FLAG     := c_NO;
            V_MESSAGE          := 'Failure occured in INSERT_INFAR006_DATA :' ||SQLERRM;

            P_SUCCESS_FLAG     := V_SUCCESS_FLAG;
            P_MESSAGE          := V_MESSAGE;

            DBMS_OUTPUT.PUT_LINE(' V_SUCCESS_FLAG = '||V_SUCCESS_FLAG||' '||V_MESSAGE );
                  
            LOG_CARS_ERROR(
                p_errorLevel    => '3',
                p_severity      => c_HIGH_SEVERITY,
                p_errorDetail   => 'FISCAL INSERT_INFAR006_DATA procedure did not succeed',
                p_errorCode     => '5000',
                p_errorMessage  => V_MESSAGE ,
                p_dataSource    => c_CARS_DB
				);                                  
    END INSERT_INFAR006_DATA;

    --  Inserts Header Line for INFAR001
    --  Row ID = 000
    PROCEDURE INSERT_INFAR001_DATA (
            P_BATCH_ID              INFAR001_OUTBOUND.BATCH_ID%TYPE,
            P_BATCH_DATE            BATCH.BATCH_DATE%TYPE,
            P_CREATED_DTTM          INFAR001_OUTBOUND.CREATED_DTTM%TYPE,
            P_DEPOSIT_BU            INFAR001_OUTBOUND.DEPOSIT_BU%TYPE,
            P_DEPOSIT_CNT           INFAR001_OUTBOUND.DEPOSIT_CNT%TYPE,
            P_TOTAL_AMT             INFAR001_OUTBOUND.TOTAL_AMT%TYPE,
            P_SUCCESS_FLAG     OUT VARCHAR2,
            P_MESSAGE          OUT VARCHAR2
            ) AS
            
        V_PROGRAM_UNIT_CODE     INFAR001_OUTBOUND.PROGRAM_UNIT_CODE%TYPE:= c_CARS_DB;
        V_FH_ROW_ID             INFAR001_OUTBOUND.FS_ROW_ID%TYPE        := c_FH_ROW_ID; -- Default for File Header
        V_STATUS                INFAR001_OUTBOUND.STATUS%TYPE           := c_STATUS_NEW;
        V_DATA_SOURCE_CODE      INFAR001_OUTBOUND.DATA_SOURCE_CODE%TYPE := c_CARS_DB;
        V_CREATED_BY            INFAR001_OUTBOUND.CREATED_BY%TYPE       := c_USER;
        V_CREATED_DATE          INFAR001_OUTBOUND.CREATED_DATE%TYPE     := SYSDATE;

        V_SUCCESS_FLAG          VARCHAR2(1)                             := c_NO;
        V_MESSAGE               VARCHAR2(500);
       
    BEGIN

        INSERT INTO INFAR001_OUTBOUND (
           BATCH_ID,
           INFAR001_OUTBOUND_ID,
           FS_ROW_ID,
           CREATED_DTTM,
           DEPOSIT_BU,
           DEPOSIT_CNT,
           TOTAL_AMT,
           STATUS,
           DATA_SOURCE_CODE,
           CREATED_BY,
           CREATED_DATE,
           PROGRAM_UNIT_CODE
           )
         VALUES (  
            P_BATCH_ID,
            INFAR001_OUTBOUND_ID_SEQ.NEXTVAL,
            V_FH_ROW_ID,
            P_CREATED_DTTM,
            P_DEPOSIT_BU,
            P_DEPOSIT_CNT,
            P_TOTAL_AMT,
            V_STATUS,
            V_DATA_SOURCE_CODE,
            V_CREATED_BY,
            V_CREATED_DATE,
            V_PROGRAM_UNIT_CODE
          );
          
        V_SUCCESS_FLAG     := c_YES;
        V_MESSAGE          := 'SUCCESSFULLY INSERTED V_FH_ROW_ID: '|| V_FH_ROW_ID;

        P_SUCCESS_FLAG     := V_SUCCESS_FLAG;
        P_MESSAGE          := V_MESSAGE;

        DBMS_OUTPUT.PUT_LINE('INSERT_INFAR001_DATA : V_SUCCESS_FLAG = '||V_SUCCESS_FLAG||' ' ||V_MESSAGE); 

    EXCEPTION
        WHEN OTHERS THEN 

                V_SUCCESS_FLAG     := c_NO;
                V_MESSAGE          := 'Failure occured in INSERT_INFAR001_DATA Header Line: ' ||SQLERRM;

                P_SUCCESS_FLAG     := V_SUCCESS_FLAG;
                P_MESSAGE          := V_MESSAGE;

                DBMS_OUTPUT.PUT_LINE(' V_SUCCESS_FLAG = '||V_SUCCESS_FLAG||' '||V_MESSAGE );
                
 				LOG_CARS_ERROR(
					p_errorLevel    => '3',
					p_severity      => c_HIGH_SEVERITY,
					p_errorDetail   => 'FISCAL INSERT_INFAR001_DATA procedure did not succeed',
					p_errorCode     => '5000',
					p_errorMessage  => V_MESSAGE ,
					p_dataSource    => c_CARS_DB
				    );                                         
    END INSERT_INFAR001_DATA;
    
    --  Inserts Deposit Control for INFAR001
    --  Row ID = 001
    PROCEDURE INSERT_INFAR001_DATA (
            P_BATCH_ID              INFAR001_OUTBOUND.BATCH_ID%TYPE,
            P_BATCH_DATE            BATCH.BATCH_DATE%TYPE,
            P_PROGRAM_UNIT          INFAR001_OUTBOUND.PROGRAM_UNIT_CODE%TYPE, 
            P_DEPOSIT_BU            INFAR001_OUTBOUND.DEPOSIT_BU%TYPE,
            P_DEPOSIT_ID            INFAR001_OUTBOUND.DEPOSIT_ID%TYPE,
            P_ACCOUNTING_DT         INFAR001_OUTBOUND.ACCOUNTING_DT%TYPE,
            P_BANK_CD               INFAR001_OUTBOUND.BANK_CD%TYPE,
            P_BANK_ACCT_KEY         INFAR001_OUTBOUND.BANK_ACCT_KEY%TYPE,
            P_DEPOSIT_TYPE          INFAR001_OUTBOUND.DEPOSIT_TYPE%TYPE,
            P_CONTROL_CURRENCY      INFAR001_OUTBOUND.CONTROL_CURRENCY%TYPE,
            P_ZZ_BNK_DEPOSIT_NUM    INFAR001_OUTBOUND.ZZ_BNK_DEPOSIT_NUM%TYPE,
            P_ZZ_IDENTIFIER         INFAR001_OUTBOUND.ZZ_IDENTIFIER%TYPE,
            P_CONTROL_AMT           INFAR001_OUTBOUND.CONTROL_AMT%TYPE,
            P_CONTROL_CNT           INFAR001_OUTBOUND.CONTROL_CNT%TYPE,
            P_RECEIVED_DT           INFAR001_OUTBOUND.RECEIVED_DT%TYPE,
            P_TOTAL_CHECKS          INFAR001_OUTBOUND.TOTAL_CHECKS%TYPE,
            P_FLAG                  INFAR001_OUTBOUND.FLAG%TYPE,
            P_BANK_OPER_NUM         INFAR001_OUTBOUND.BANK_OPER_NUM%TYPE,
            P_ZZ_LEG_DEP_ID         INFAR001_OUTBOUND.ZZ_LEG_DEP_ID%TYPE,
            P_ACCTG_ENTRY_ID        INFAR001_OUTBOUND.ACCTG_ENTRY_ID%TYPE,
            P_SUCCESS_FLAG     OUT VARCHAR2,
            P_MESSAGE          OUT VARCHAR2
            ) AS
        
        V_DC_ROW_ID             INFAR001_OUTBOUND.FS_ROW_ID%TYPE        := c_DC_ROW_ID; -- Default for Deposit Control
        V_STATUS                INFAR001_OUTBOUND.STATUS%TYPE           := c_STATUS_NEW;
        V_DATA_SOURCE_CODE      INFAR001_OUTBOUND.DATA_SOURCE_CODE%TYPE := c_CARS_DB;
        V_CREATED_BY            INFAR001_OUTBOUND.CREATED_BY%TYPE       := c_USER;
        V_CREATED_DATE          INFAR001_OUTBOUND.CREATED_DATE%TYPE     := SYSDATE;

        V_SUCCESS_FLAG           VARCHAR2(1)                            := c_NO;
        V_MESSAGE                VARCHAR2(500);
       
    BEGIN

        INSERT INTO INFAR001_OUTBOUND (
           BATCH_ID,
           INFAR001_OUTBOUND_ID,
           FS_ROW_ID,
           CREATED_DTTM,
           DEPOSIT_BU,
           DEPOSIT_ID,
           ACCOUNTING_DT,
           BANK_CD,
           BANK_ACCT_KEY,
           DEPOSIT_TYPE,
           CONTROL_CURRENCY,
           ZZ_BNK_DEPOSIT_NUM,
           ZZ_IDENTIFIER,
           CONTROL_AMT,
           CONTROL_CNT,
           RECEIVED_DT,
           STATUS,
           DATA_SOURCE_CODE,
           CREATED_BY,
           CREATED_DATE,
           ACCTG_ENTRY_ID,
           PROGRAM_UNIT_CODE,
           TOTAL_CHECKS,
           FLAG,
           BANK_OPER_NUM,
           ZZ_LEG_DEP_ID
           )
         VALUES (  
            P_BATCH_ID,
            INFAR001_OUTBOUND_ID_SEQ.NEXTVAL,
            V_DC_ROW_ID,
            V_CREATED_DATE,
            P_DEPOSIT_BU,
            P_DEPOSIT_ID,
            P_ACCOUNTING_DT,
            P_BANK_CD,
            P_BANK_ACCT_KEY,
            P_DEPOSIT_TYPE,
            P_CONTROL_CURRENCY,
            P_ZZ_BNK_DEPOSIT_NUM,
            P_ZZ_IDENTIFIER,
            P_CONTROL_AMT,
            P_CONTROL_CNT,
            P_RECEIVED_DT,
            V_STATUS,
            V_DATA_SOURCE_CODE,
            V_CREATED_BY,
            V_CREATED_DATE,
            P_ACCTG_ENTRY_ID,
            P_PROGRAM_UNIT,
            P_TOTAL_CHECKS,
            P_FLAG,
            P_BANK_OPER_NUM,
            P_ZZ_LEG_DEP_ID
          );

        V_SUCCESS_FLAG     := c_YES;
        V_MESSAGE          := 'SUCCESSFULLY INSERTED V_DC_ROW_ID: '|| V_DC_ROW_ID;

        P_SUCCESS_FLAG     := V_SUCCESS_FLAG;
        P_MESSAGE          := V_MESSAGE;

        DBMS_OUTPUT.PUT_LINE('INSERT_INFAR001_DATA : V_SUCCESS_FLAG = '||V_SUCCESS_FLAG||' '||V_MESSAGE ); 
        
    EXCEPTION
        WHEN OTHERS THEN 

                V_SUCCESS_FLAG     := c_NO;
                V_MESSAGE          := 'Failure occured in INSERT_INFAR001_DATA Deposit Control:' ||SQLERRM;

                P_SUCCESS_FLAG     := V_SUCCESS_FLAG;
                P_MESSAGE          := V_MESSAGE;

                DBMS_OUTPUT.PUT_LINE(' V_SUCCESS_FLAG = '||V_SUCCESS_FLAG||' '||V_MESSAGE );
                
 				LOG_CARS_ERROR(
					p_errorLevel    => '3',
					p_severity      => c_HIGH_SEVERITY,
					p_errorDetail   => 'FISCAL INSERT_INFAR001_DATA procedure did not succeed',
					p_errorCode     => '5000',
					p_errorMessage  => V_MESSAGE ,
					p_dataSource    => c_CARS_DB
				    );                                          
    END INSERT_INFAR001_DATA;
    
    --  Inserts Payment Information for INFAR001
    --  Row ID = 002
    PROCEDURE INSERT_INFAR001_DATA (
            P_BATCH_ID              INFAR001_OUTBOUND.BATCH_ID%TYPE,
            P_BATCH_DATE            BATCH.BATCH_DATE%TYPE,
            P_PROGRAM_UNIT          INFAR001_OUTBOUND.PROGRAM_UNIT_CODE%TYPE, 
            P_DEPOSIT_BU            INFAR001_OUTBOUND.DEPOSIT_BU%TYPE,
            P_DEPOSIT_ID            INFAR001_OUTBOUND.DEPOSIT_ID%TYPE,
            P_PAYMENT_SEQ_NUM       INFAR001_OUTBOUND.PAYMENT_SEQ_NUM%TYPE,
            P_PAYMENT_ID            INFAR001_OUTBOUND.PAYMENT_ID%TYPE,
            P_ACCOUNTING_DT         INFAR001_OUTBOUND.ACCOUNTING_DT%TYPE,
            P_PAYMENT_AMT           INFAR001_OUTBOUND.PAYMENT_AMT%TYPE,
            P_PAYMENT_CURRENCY      INFAR001_OUTBOUND.PAYMENT_CURRENCY%TYPE,
            P_PP_SW                 INFAR001_OUTBOUND.PP_SW%TYPE,
            P_MISC_PAYMENT          INFAR001_OUTBOUND.MISC_PAYMENT%TYPE,
            P_CHECK_DT              INFAR001_OUTBOUND.CHECK_DT%TYPE,
            P_ZZ_PAYMENT_METHOD     INFAR001_OUTBOUND.ZZ_PAYMENT_METHOD%TYPE,
            P_ZZ_RECEIVED_BY_SCO    INFAR001_OUTBOUND.ZZ_RECEIVED_BY_SCO%TYPE,
            P_ZZ_CASH_TYPE          INFAR001_OUTBOUND.ZZ_CASH_TYPE%TYPE,
            P_DESCR50_MIXED         INFAR001_OUTBOUND.DESCR50_MIXED%TYPE,
            P_DOCUMENT              INFAR001_OUTBOUND.DOCUMENT%TYPE,
            P_CITY                  INFAR001_OUTBOUND.CITY%TYPE,
            P_COUNTY                INFAR001_OUTBOUND.COUNTY%TYPE,
            P_TAX_AMT               INFAR001_OUTBOUND.TAX_AMT%TYPE,
            P_LINE_NOTE_TEXT        INFAR001_OUTBOUND.LINE_NOTE_TEXT%TYPE,
            P_ACCTG_ENTRY_ID        INFAR001_OUTBOUND.ACCTG_ENTRY_ID%TYPE,
            P_ROOT_DOCUMENT         EVENT.AR_ROOT_DOCUMENT%TYPE,
            P_SUCCESS_FLAG     OUT VARCHAR2,
            P_MESSAGE          OUT VARCHAR2
            ) AS
        
        V_PI_ROW_ID             INFAR001_OUTBOUND.FS_ROW_ID%TYPE        := c_PI_ROW_ID; -- Default for Payment Information
        V_STATUS                INFAR001_OUTBOUND.STATUS%TYPE           := c_STATUS_NEW;
        V_DATA_SOURCE_CODE      INFAR001_OUTBOUND.DATA_SOURCE_CODE%TYPE := c_CARS_DB;
        V_CREATED_BY            INFAR001_OUTBOUND.CREATED_BY%TYPE       := c_USER;
        V_CREATED_DATE          INFAR001_OUTBOUND.CREATED_DATE%TYPE     := SYSDATE;

        V_SUCCESS_FLAG          VARCHAR2(1)                             := c_NO;
        V_MESSAGE               VARCHAR2(500);
       
    BEGIN

        INSERT INTO INFAR001_OUTBOUND (
           BATCH_ID,
           INFAR001_OUTBOUND_ID,
           FS_ROW_ID,
           CREATED_DTTM,
           DEPOSIT_BU,
           DEPOSIT_ID,
           PAYMENT_SEQ_NUM,
           PAYMENT_ID,
           ACCOUNTING_DT,
           PAYMENT_AMT,
           PAYMENT_CURRENCY,
           PP_SW,
           MISC_PAYMENT,
           CHECK_DT,
           ZZ_PAYMENT_METHOD,
           ZZ_RECEIVED_BY_SCO,
           ZZ_CASH_TYPE,
           DESCR50_MIXED,
           DOCUMENT,
           CITY,
           COUNTY,
           TAX_AMT,
           LINE_NOTE_TEXT,
           STATUS,
           DATA_SOURCE_CODE,
           CREATED_BY,
           CREATED_DATE,
           ACCTG_ENTRY_ID,
           PROGRAM_UNIT_CODE,
           AR_ROOT_DOCUMENT
           )
         VALUES (  
            P_BATCH_ID,
            INFAR001_OUTBOUND_ID_SEQ.NEXTVAL,
            V_PI_ROW_ID,
            V_CREATED_DATE,
            P_DEPOSIT_BU,
            P_DEPOSIT_ID,
            P_PAYMENT_SEQ_NUM,
            P_PAYMENT_ID,
            P_ACCOUNTING_DT,
            P_PAYMENT_AMT,
            P_PAYMENT_CURRENCY,
            P_PP_SW,
            P_MISC_PAYMENT,
            P_CHECK_DT,
            P_ZZ_PAYMENT_METHOD,
            P_ZZ_RECEIVED_BY_SCO,
            P_ZZ_CASH_TYPE,
            P_DESCR50_MIXED,
            P_DOCUMENT,
            P_CITY,
            P_COUNTY,
            P_TAX_AMT,
            P_LINE_NOTE_TEXT,
            V_STATUS,
            V_DATA_SOURCE_CODE,
            V_CREATED_BY,
            V_CREATED_DATE,
            P_ACCTG_ENTRY_ID,
            P_PROGRAM_UNIT,
            P_ROOT_DOCUMENT
          );

        V_SUCCESS_FLAG     := c_YES;
        V_MESSAGE          := 'SUCCESSFULLY INSERTED V_PI_ROW_ID: '|| V_PI_ROW_ID;

        P_SUCCESS_FLAG     := V_SUCCESS_FLAG;
        P_MESSAGE          := V_MESSAGE;

        DBMS_OUTPUT.PUT_LINE('INSERT_INFAR001_DATA : V_SUCCESS_FLAG = '||V_SUCCESS_FLAG||' '||V_MESSAGE); 

    EXCEPTION
        WHEN OTHERS THEN 

                V_SUCCESS_FLAG     := c_NO;
                V_MESSAGE          := 'Failure occured in INSERT_INFAR001_DATA :' ||SQLERRM;

                P_SUCCESS_FLAG     := V_SUCCESS_FLAG;
                P_MESSAGE          := V_MESSAGE;

                DBMS_OUTPUT.PUT_LINE(' V_SUCCESS_FLAG = '||V_SUCCESS_FLAG||' '||V_MESSAGE );
                
 				LOG_CARS_ERROR(
					p_errorLevel    => '3',
					p_severity      => c_HIGH_SEVERITY,
					p_errorDetail   => 'FISCAL INSERT_INFAR001_DATA procedure did not succeed',
					p_errorCode     => '5000',
					p_errorMessage  => V_MESSAGE ,
					p_dataSource    => c_CARS_DB
				    );                                          
    END INSERT_INFAR001_DATA;
    
    --  Inserts Item Reference for INFAR001
    --  Row ID = 003
    PROCEDURE INSERT_INFAR001_DATA (
            P_BATCH_ID              INFAR001_OUTBOUND.BATCH_ID%TYPE,
            P_BATCH_DATE            BATCH.BATCH_DATE%TYPE,
            P_PROGRAM_UNIT          INFAR001_OUTBOUND.PROGRAM_UNIT_CODE%TYPE, 
            P_DEPOSIT_BU            INFAR001_OUTBOUND.DEPOSIT_BU%TYPE,
            P_DEPOSIT_ID            INFAR001_OUTBOUND.DEPOSIT_ID%TYPE,
            P_PAYMENT_SEQ_NUM       INFAR001_OUTBOUND.PAYMENT_SEQ_NUM%TYPE,
            P_ID_SEQ_NUM            INFAR001_OUTBOUND.ID_SEQ_NUM%TYPE,
            P_REF_QUALIFIER_CODE    INFAR001_OUTBOUND.REF_QUALIFIER_CODE%TYPE,
            P_REF_VALUE             INFAR001_OUTBOUND.REF_VALUE%TYPE,
            P_ACCTG_ENTRY_ID        INFAR001_OUTBOUND.ACCTG_ENTRY_ID%TYPE,
            P_ROOT_DOCUMENT         EVENT.AR_ROOT_DOCUMENT%TYPE,
            P_SUCCESS_FLAG     OUT VARCHAR2,
            P_MESSAGE          OUT VARCHAR2
            ) AS

        V_IR_ROW_ID             INFAR001_OUTBOUND.FS_ROW_ID%TYPE        := c_IR_ROW_ID; -- Default for Item Reference
        V_STATUS                INFAR001_OUTBOUND.STATUS%TYPE           := c_STATUS_NEW; -- All Possible Statuses to be decided and recorded.
        V_DATA_SOURCE_CODE      INFAR001_OUTBOUND.DATA_SOURCE_CODE%TYPE := c_CARS_DB;
        V_CREATED_BY            INFAR001_OUTBOUND.CREATED_BY%TYPE       := c_USER;
        V_CREATED_DATE          INFAR001_OUTBOUND.CREATED_DATE%TYPE     := SYSDATE;
        
        V_SUCCESS_FLAG          VARCHAR2(1)                             := c_NO;
        V_MESSAGE               VARCHAR2(500);
       
    BEGIN
    
        INSERT INTO INFAR001_OUTBOUND (
           BATCH_ID,
           INFAR001_OUTBOUND_ID,
           FS_ROW_ID,
           CREATED_DTTM,
           DEPOSIT_BU,
           DEPOSIT_ID,
           PAYMENT_SEQ_NUM,
           ID_SEQ_NUM,
           REF_QUALIFIER_CODE,
           REF_VALUE,
           STATUS,
           DATA_SOURCE_CODE,
           CREATED_BY,
           CREATED_DATE,
           ACCTG_ENTRY_ID,
           PROGRAM_UNIT_CODE,
           AR_ROOT_DOCUMENT
           )
         VALUES (  
            P_BATCH_ID,
            INFAR001_OUTBOUND_ID_SEQ.NEXTVAL,
            V_IR_ROW_ID,
            V_CREATED_DATE,
            P_DEPOSIT_BU,
            P_DEPOSIT_ID,
            P_PAYMENT_SEQ_NUM,
            P_ID_SEQ_NUM,
            P_REF_QUALIFIER_CODE,
            P_REF_VALUE,
            V_STATUS,
            V_DATA_SOURCE_CODE,
            V_CREATED_BY,
            V_CREATED_DATE,
            P_ACCTG_ENTRY_ID,
            P_PROGRAM_UNIT,
            P_ROOT_DOCUMENT
          );

        V_SUCCESS_FLAG     := c_YES;
        V_MESSAGE          := 'SUCCESSFULLY INSERTED V_IR_ROW_ID: '|| V_IR_ROW_ID;

        P_SUCCESS_FLAG     := V_SUCCESS_FLAG;
        P_MESSAGE          := V_MESSAGE;

        DBMS_OUTPUT.PUT_LINE('INSERT_INFAR001_DATA :V_SUCCESS_FLAG = '||V_SUCCESS_FLAG||' ' ||V_MESSAGE);
         
    EXCEPTION
        WHEN OTHERS THEN 

                V_SUCCESS_FLAG     := c_NO;
                V_MESSAGE          := 'Failure occured in INSERT_INFAR001_DATA Item Reference:' ||SQLERRM;

                P_SUCCESS_FLAG     := V_SUCCESS_FLAG;
                P_MESSAGE          := V_MESSAGE;

                DBMS_OUTPUT.PUT_LINE(' V_SUCCESS_FLAG = '||V_SUCCESS_FLAG||' '||V_MESSAGE );
                
 				LOG_CARS_ERROR(
					p_errorLevel    => '3',
					p_severity      => c_HIGH_SEVERITY,
					p_errorDetail   => 'FISCAL INSERT_INFAR001_DATA procedure did not succeed',
					p_errorCode     => '5000',
					p_errorMessage  => V_MESSAGE ,
					p_dataSource    => c_CARS_DB
				    );     
    END INSERT_INFAR001_DATA;
    
    --  Inserts Customer Information for INFAR001
    --  Row ID = 004
    PROCEDURE INSERT_INFAR001_DATA (
            P_BATCH_ID              INFAR001_OUTBOUND.BATCH_ID%TYPE,
            P_BATCH_DATE            BATCH.BATCH_DATE%TYPE,
            P_PROGRAM_UNIT          INFAR001_OUTBOUND.PROGRAM_UNIT_CODE%TYPE, 
            P_DEPOSIT_BU            INFAR001_OUTBOUND.DEPOSIT_BU%TYPE,
            P_DEPOSIT_ID            INFAR001_OUTBOUND.DEPOSIT_ID%TYPE,
            P_PAYMENT_SEQ_NUM       INFAR001_OUTBOUND.PAYMENT_SEQ_NUM%TYPE,
            P_ID_SEQ_NUM            INFAR001_OUTBOUND.ID_SEQ_NUM%TYPE,
            P_CUST_ID               INFAR001_OUTBOUND.CUST_ID%TYPE,
            P_ACCTG_ENTRY_ID        INFAR001_OUTBOUND.ACCTG_ENTRY_ID%TYPE,
            P_ROOT_DOCUMENT         EVENT.AR_ROOT_DOCUMENT%TYPE,
            P_SUCCESS_FLAG     OUT VARCHAR2,
            P_MESSAGE          OUT VARCHAR2
            ) AS

        V_CI_ROW_ID             INFAR001_OUTBOUND.FS_ROW_ID%TYPE        := c_CI_ROW_ID; -- Default for Customer Information
        V_STATUS                INFAR001_OUTBOUND.STATUS%TYPE           := c_STATUS_NEW;
        V_DATA_SOURCE_CODE      INFAR001_OUTBOUND.DATA_SOURCE_CODE%TYPE := c_CARS_DB;
        V_CREATED_BY            INFAR001_OUTBOUND.CREATED_BY%TYPE       := c_USER;
        V_CREATED_DATE          INFAR001_OUTBOUND.CREATED_DATE%TYPE     := SYSDATE;

        V_SUCCESS_FLAG          VARCHAR2(1)                             := c_NO;
        V_MESSAGE               VARCHAR2(500);
    BEGIN

    INSERT INTO INFAR001_OUTBOUND (
           BATCH_ID,
           INFAR001_OUTBOUND_ID,
           FS_ROW_ID,
           CREATED_DTTM,
           DEPOSIT_BU,
           DEPOSIT_ID,
           PAYMENT_SEQ_NUM,
           ID_SEQ_NUM,
           CUST_ID,
           STATUS,
           DATA_SOURCE_CODE,
           CREATED_BY,
           CREATED_DATE,
           ACCTG_ENTRY_ID,
           PROGRAM_UNIT_CODE,
           AR_ROOT_DOCUMENT
           )
         VALUES (  
            P_BATCH_ID,
            INFAR001_OUTBOUND_ID_SEQ.NEXTVAL,
            V_CI_ROW_ID,
            V_CREATED_DATE,
            P_DEPOSIT_BU,
            P_DEPOSIT_ID,
            P_PAYMENT_SEQ_NUM,
            P_ID_SEQ_NUM,
            P_CUST_ID,
            V_STATUS,
            V_DATA_SOURCE_CODE,
            V_CREATED_BY,
            V_CREATED_DATE,
            P_ACCTG_ENTRY_ID,
            P_PROGRAM_UNIT,
            P_ROOT_DOCUMENT
          );

        V_SUCCESS_FLAG     := c_YES;
        V_MESSAGE          := 'SUCCESSFULLY INSERTED V_CI_ROW_ID: '|| V_CI_ROW_ID;

        P_SUCCESS_FLAG     := V_SUCCESS_FLAG;
        P_MESSAGE          := V_MESSAGE;

        DBMS_OUTPUT.PUT_LINE('INSERT_INFAR001_DATA :V_SUCCESS_FLAG = '||V_SUCCESS_FLAG||' '||V_MESSAGE); 

    EXCEPTION
        WHEN OTHERS THEN 

                V_SUCCESS_FLAG     := c_NO;
                V_MESSAGE          := 'Failure occured in INSERT_INFAR001_DATA Customer Information:' ||SQLERRM;

                P_SUCCESS_FLAG     := V_SUCCESS_FLAG;
                P_MESSAGE          := V_MESSAGE;

				LOG_CARS_ERROR(
					p_errorLevel    => '3',
					p_severity      => c_HIGH_SEVERITY,
					p_errorDetail   => 'FISCAL INSERT_INFAR001_DATA procedure did not succeed',
					p_errorCode     => '5000',
					p_errorMessage  => V_MESSAGE ,
					p_dataSource    => c_CARS_DB
    				);  
                DBMS_OUTPUT.PUT_LINE(' V_SUCCESS_FLAG = '||V_SUCCESS_FLAG||' '||V_MESSAGE );
                
    END INSERT_INFAR001_DATA;
    
    --  Inserts Direct Journal - Distribution for INFAR001
    --  Row ID = 005
    PROCEDURE INSERT_INFAR001_DATA (
            P_BATCH_ID              INFAR001_OUTBOUND.BATCH_ID%TYPE,
            P_BATCH_DATE            BATCH.BATCH_DATE%TYPE,
            P_PROGRAM_UNIT          INFAR001_OUTBOUND.PROGRAM_UNIT_CODE%TYPE, 
            P_DEPOSIT_BU            INFAR001_OUTBOUND.DEPOSIT_BU%TYPE,
            P_DEPOSIT_ID            INFAR001_OUTBOUND.DEPOSIT_ID%TYPE,
            P_PAYMENT_SEQ_NUM       INFAR001_OUTBOUND.PAYMENT_SEQ_NUM%TYPE,
            P_DST_SEQ_NUM           INFAR001_OUTBOUND.DST_SEQ_NUM%TYPE,
            P_BUSINESS_UNIT_GL      INFAR001_OUTBOUND.BUSINESS_UNIT_GL%TYPE,
            P_SPEEDCHART_KEY        INFAR001_OUTBOUND.SPEEDCHART_KEY%TYPE,
            P_MONETARY_AMOUNT       INFAR001_OUTBOUND.MONETARY_AMOUNT%TYPE,
            P_ACCOUNT               INFAR001_OUTBOUND.ACCOUNT%TYPE,
            P_RESOURCE_TYPE         INFAR001_OUTBOUND.RESOURCE_TYPE%TYPE,
            P_RESOURCE_CATEGORY     INFAR001_OUTBOUND.RESOURCE_CATEGORY%TYPE,
            P_RESOURCE_SUB_CAT      INFAR001_OUTBOUND.RESOURCE_SUB_CAT%TYPE,
            P_ANALYSIS_TYPE         INFAR001_OUTBOUND.ANALYSIS_TYPE%TYPE,
            P_OPERATING_UNIT        INFAR001_OUTBOUND.OPERATING_UNIT%TYPE,
            P_PRODUCT               INFAR001_OUTBOUND.PRODUCT%TYPE,
            P_FUND_CODE             INFAR001_OUTBOUND.FUND_CODE%TYPE,
            P_CLASS_FLD             INFAR001_OUTBOUND.CLASS_FLD%TYPE,
            P_PROGRAM_CODE          INFAR001_OUTBOUND.PROGRAM_CODE%TYPE,
            P_BUDGET_REF            INFAR001_OUTBOUND.BUDGET_REF%TYPE,
            P_AFFILIATE             INFAR001_OUTBOUND.AFFILIATE%TYPE,
            P_AFFILIATE_INTRA1      INFAR001_OUTBOUND.AFFILIATE_INTRA1%TYPE,
            P_AFFILIATE_INTRA2      INFAR001_OUTBOUND.AFFILIATE_INTRA2%TYPE,
            P_CHARTFIELD1           INFAR001_OUTBOUND.CHARTFIELD1%TYPE,
            P_CHARTFIELD2           INFAR001_OUTBOUND.CHARTFIELD2%TYPE,
            P_CHARTFIELD3           INFAR001_OUTBOUND.CHARTFIELD3%TYPE,
            P_ALTACCT               INFAR001_OUTBOUND.ALTACCT%TYPE,
            P_DEPTID                INFAR001_OUTBOUND.DEPTID%TYPE,
            P_FUND                  INFAR001_OUTBOUND.FUND%TYPE,
            P_SUBFUND               INFAR001_OUTBOUND.SUBFUND%TYPE,
            P_PROGRAM               INFAR001_OUTBOUND.PROGRAM%TYPE,
            P_ELEMENT               INFAR001_OUTBOUND.ELEMENT%TYPE,
            P_COMPONENT             INFAR001_OUTBOUND.COMPONENT%TYPE,
            P_TASK                  INFAR001_OUTBOUND.TASK%TYPE,
            P_PCA                   INFAR001_OUTBOUND.PCA%TYPE,
            P_ORG_CODE              INFAR001_OUTBOUND.ORG_CODE%TYPE,
            P_INDEX_CODE            INFAR001_OUTBOUND.INDEX_CODE%TYPE,
            P_OBJECT_DETAIL         INFAR001_OUTBOUND.OBJECT_DETAIL%TYPE,
            P_AGENCY_OBJECT         INFAR001_OUTBOUND.AGENCY_OBJECT%TYPE,
            P_SOURCE                INFAR001_OUTBOUND.SOURCE%TYPE,
            P_AGENCY_SOURCE         INFAR001_OUTBOUND.AGENCY_SOURCE%TYPE,
            P_GL_ACCOUNT            INFAR001_OUTBOUND.GL_ACCOUNT%TYPE,
            P_SUBSIDIARY            INFAR001_OUTBOUND.SUBSIDIARY%TYPE,
            P_FUND_SOURCE           INFAR001_OUTBOUND.FUND_SOURCE%TYPE,
            P_CHARACTER             INFAR001_OUTBOUND.CHARACTER%TYPE,
            P_METHOD                INFAR001_OUTBOUND.METHOD%TYPE,
            P_YEAR                  INFAR001_OUTBOUND.YEAR%TYPE,
            P_REFERENCE             INFAR001_OUTBOUND.REFERENCE%TYPE,
            P_FFY                   INFAR001_OUTBOUND.FFY%TYPE,
            P_APPROPRIATION_SYMBOL  INFAR001_OUTBOUND.APPROPRIATION_SYMBOL%TYPE,
            P_PROJECT               INFAR001_OUTBOUND.PROJECT%TYPE,
            P_WORK_PHASE            INFAR001_OUTBOUND.WORK_PHASE%TYPE,
            P_MULTIPURPOSE          INFAR001_OUTBOUND.MULTIPURPOSE%TYPE,
            P_LOCATION              INFAR001_OUTBOUND.LOCATION%TYPE,
            P_DEPT_USE_1            INFAR001_OUTBOUND.DEPT_USE_1%TYPE,
            P_DEPT_USE_2            INFAR001_OUTBOUND.DEPT_USE_2%TYPE,
            P_BUDGET_DT             INFAR001_OUTBOUND.BUDGET_DT%TYPE,
            P_LINE_DESCR            INFAR001_OUTBOUND.LINE_DESCR%TYPE,
            P_OPEN_ITEM_KEY         INFAR001_OUTBOUND.OPEN_ITEM_KEY%TYPE,
            P_ACCTG_ENTRY_ID        INFAR001_OUTBOUND.ACCTG_ENTRY_ID%TYPE,
            P_ROOT_DOCUMENT         EVENT.AR_ROOT_DOCUMENT%TYPE,
            P_SUCCESS_FLAG     OUT VARCHAR2,
            P_MESSAGE          OUT VARCHAR2
            ) AS

        V_DJD_ROW_ID            INFAR001_OUTBOUND.FS_ROW_ID%TYPE        := c_DJ_ROW_ID; -- Default for Direct Journal - Distribution
        V_STATUS                INFAR001_OUTBOUND.STATUS%TYPE           := c_STATUS_NEW; -- All Possible Statuses to be decided and recorded.
        V_DATA_SOURCE_CODE      INFAR001_OUTBOUND.DATA_SOURCE_CODE%TYPE := c_CARS_DB;
        V_CREATED_BY            INFAR001_OUTBOUND.CREATED_BY%TYPE       := c_USER;
        V_CREATED_DATE          INFAR001_OUTBOUND.CREATED_DATE%TYPE     := SYSDATE;

        V_SUCCESS_FLAG          VARCHAR2(1)                             := c_NO;
        V_MESSAGE               VARCHAR2(500);
    BEGIN

    INSERT INTO INFAR001_OUTBOUND (
           BATCH_ID,
           INFAR001_OUTBOUND_ID,
           FS_ROW_ID,
           CREATED_DTTM,
           DEPOSIT_BU,
           DEPOSIT_ID,
           PAYMENT_SEQ_NUM,DST_SEQ_NUM,
           BUSINESS_UNIT_GL,
           SPEEDCHART_KEY,
           MONETARY_AMOUNT,
           ACCOUNT,
           RESOURCE_TYPE,
           RESOURCE_CATEGORY,
           RESOURCE_SUB_CAT,
           ANALYSIS_TYPE,
           OPERATING_UNIT,
           PRODUCT,
           FUND_CODE,
           CLASS_FLD,
           PROGRAM_CODE,
           BUDGET_REF,
           AFFILIATE,
           AFFILIATE_INTRA1,
           AFFILIATE_INTRA2,
           CHARTFIELD1,
           CHARTFIELD2,
           CHARTFIELD3,
           ALTACCT,
           DEPTID,
           FUND,
           SUBFUND,
           PROGRAM,
           ELEMENT,
           COMPONENT,
           TASK,
           PCA,
           ORG_CODE,
           INDEX_CODE,
           OBJECT_DETAIL,
           AGENCY_OBJECT,
           SOURCE,
           AGENCY_SOURCE,
           GL_ACCOUNT,
           SUBSIDIARY,
           FUND_SOURCE,
           CHARACTER,
           METHOD,
           YEAR,
           REFERENCE,
           FFY,
           APPROPRIATION_SYMBOL,
           PROJECT,
           WORK_PHASE,
           MULTIPURPOSE,
           LOCATION,
           DEPT_USE_1,
           DEPT_USE_2,
           BUDGET_DT,
           LINE_DESCR,
           OPEN_ITEM_KEY,
           STATUS,
           DATA_SOURCE_CODE,
           CREATED_BY,
           CREATED_DATE,
           ACCTG_ENTRY_ID,
           PROGRAM_UNIT_CODE,
           AR_ROOT_DOCUMENT
           )
         VALUES (  
            P_BATCH_ID,
            INFAR001_OUTBOUND_ID_SEQ.NEXTVAL,
            V_DJD_ROW_ID,
            V_CREATED_DATE,
            P_DEPOSIT_BU,
            P_DEPOSIT_ID,
            P_PAYMENT_SEQ_NUM,P_DST_SEQ_NUM,
            P_BUSINESS_UNIT_GL,
            P_SPEEDCHART_KEY,
            P_MONETARY_AMOUNT,
            P_ACCOUNT,
            P_RESOURCE_TYPE,
            P_RESOURCE_CATEGORY,
            P_RESOURCE_SUB_CAT,
            P_ANALYSIS_TYPE,
            P_OPERATING_UNIT,
            P_PRODUCT,
            P_FUND_CODE,
            P_CLASS_FLD,
            P_PROGRAM_CODE,
            P_BUDGET_REF,
            P_AFFILIATE,
            P_AFFILIATE_INTRA1,
            P_AFFILIATE_INTRA2,
            P_CHARTFIELD1,
            P_CHARTFIELD2,
            P_CHARTFIELD3,
            P_ALTACCT,
            P_DEPTID,
            P_FUND,
            P_SUBFUND,
            P_PROGRAM,
            P_ELEMENT,
            P_COMPONENT,
            P_TASK,
            P_PCA,
            P_ORG_CODE,
            P_INDEX_CODE,
            P_OBJECT_DETAIL,
            P_AGENCY_OBJECT,
            P_SOURCE,
            P_AGENCY_SOURCE,
            P_GL_ACCOUNT,
            P_SUBSIDIARY,
            P_FUND_SOURCE,
            P_CHARACTER,
            P_METHOD,
            P_YEAR,
            P_REFERENCE,
            P_FFY,
            P_APPROPRIATION_SYMBOL,
            P_PROJECT,
            P_WORK_PHASE,
            P_MULTIPURPOSE,
            P_LOCATION,
            P_DEPT_USE_1,
            P_DEPT_USE_2,
            P_BUDGET_DT,
            P_LINE_DESCR,
            P_OPEN_ITEM_KEY,
            V_STATUS,
            V_DATA_SOURCE_CODE,
            V_CREATED_BY,
            V_CREATED_DATE,
            P_ACCTG_ENTRY_ID,
            P_PROGRAM_UNIT,
            P_ROOT_DOCUMENT
          );

        V_SUCCESS_FLAG     := c_YES;
        V_MESSAGE          := 'SUCCESSFULLY INSERTED V_DJD_ROW_ID: '|| V_DJD_ROW_ID;

        P_SUCCESS_FLAG     := V_SUCCESS_FLAG;
        P_MESSAGE          := V_MESSAGE;

        DBMS_OUTPUT.PUT_LINE('INSERT_INFAR001_DATA : V_SUCCESS_FLAG = '||V_SUCCESS_FLAG||' '||V_MESSAGE); 

    EXCEPTION
        WHEN OTHERS THEN 

                V_SUCCESS_FLAG     := c_NO;
                V_MESSAGE          := 'Failure occured in INSERT_INFAR001_DATA Direct Journal - Distribution:' ||SQLERRM;

                P_SUCCESS_FLAG     := V_SUCCESS_FLAG;
                P_MESSAGE          := V_MESSAGE;

				LOG_CARS_ERROR(
					p_errorLevel    => '3',
					p_severity      => c_HIGH_SEVERITY,
					p_errorDetail   => 'FISCAL INSERT_INFAR001_DATA procedure did not succeed',
					p_errorCode     => '5000',
					p_errorMessage  => V_MESSAGE ,
					p_dataSource    => c_CARS_DB
    				);  

                DBMS_OUTPUT.PUT_LINE(' V_SUCCESS_FLAG = '||V_SUCCESS_FLAG||' '||V_MESSAGE );
                
    END INSERT_INFAR001_DATA;
    
    PROCEDURE GET_INFAR001_DATA (
        P_BATCH_ID              INFAR006_OUTBOUND.BATCH_ID%TYPE,
        P_BATCH_DATE            BATCH.BATCH_DATE%TYPE,
        P_PROGRAM_UNIT          PROGRAM_UNIT.PROGRAM_UNIT_CODE%TYPE,
        P_TRANSACT_CODE         ACCOUNTING_ENTRY_TYPE.ACCTG_TRANSACT_CODE%TYPE,
        P_TRANSACT_REVS         ACCOUNTING_ENTRY_TYPE.TRANSACTION_REVERSAL%TYPE
        ) AS
        
        V_TRANSACTION_CNT                   ACCOUNTING_ENTRY.AMOUNT%TYPE;
        V_ACCTG_ENTRY_ID                    ACCOUNTING_ENTRY.ACCTG_ENTRY_ID%TYPE;
        V_ACCTG_TRANS_ID                    ACCOUNTING_ENTRY.ACCTG_TRANSACTION_ID%TYPE;
        V_ROOT_DOCUMENT                     EVENT.AR_ROOT_DOCUMENT%TYPE;
        V_ACCTG_ENTRY_AMT                   ACCOUNTING_ENTRY.AMOUNT%TYPE;
        V_EVENT_DATE                        EVENT.EVENT_DATE%TYPE;
        V_DEPOSIT_SLIP                      RECEIPT.DEPOSIT_SLIP_NUMBER%TYPE;
        V_DEPOSIT_DATE                      RECEIPT.DEPOSIT_DATE%TYPE;
        V_RECEIPT_DATE                      RECEIPT.RECEIPT_DATE%TYPE;
        V_RECEIPT_TYPE_CODE                 RECEIPT.RECEIPT_TYPE_CODE%TYPE;
        V_BILL_TYPE_CODE                    RECEIPT.BILL_TYPE_CODE%TYPE;
        V_LOCATION_CODE                     RECEIPT.LOCATION_CODE%TYPE;
        V_REPT_CON_NUM                      RECEIPT.RECEIPT_CONTROL_NUMBER%TYPE;
        V_FS_DEPOSIT                        INFAR001_OUTBOUND.ZZ_BNK_DEPOSIT_NUM%TYPE;
        V_ZZ_BNK_DEPOSIT_NUM                INFAR001_OUTBOUND.ZZ_BNK_DEPOSIT_NUM%TYPE;
        V_TOTAL_CHECKS                      INFAR001_OUTBOUND.TOTAL_CHECKS%TYPE;
        V_FLAG                              INFAR001_OUTBOUND.FLAG%TYPE;
        V_BANK_OPER_NUM                     INFAR001_OUTBOUND.BANK_OPER_NUM%TYPE;
        V_ZZ_LEG_DEP_ID                     INFAR001_OUTBOUND.ZZ_LEG_DEP_ID%TYPE;
        V_ZZ_IDENTIFIER                     INFAR001_OUTBOUND.ZZ_IDENTIFIER%TYPE;
        V_FS_PAYMENT_METHOD                 INFAR001_OUTBOUND.ZZ_PAYMENT_METHOD%TYPE;
        V_FS_DEPOSIT_TYPE                   INFAR001_OUTBOUND.DEPOSIT_TYPE%TYPE;
        V_PROGRAM_UNIT_CODE                 PROGRAM_UNIT.PROGRAM_UNIT_CODE%TYPE;
        V_FISCAL_YEAR_NAME                  FISCAL_PERIOD.FISCAL_YEAR_NAME%TYPE;
        V_DEPOSIT_ID_PREFIX                 PROGRAM_UNIT.PROGRAM_UNIT_CODE%TYPE;
        V_TRANSACTION_CODE                  ACCOUNTING_ENTRY_TYPE.ACCTG_TRANSACT_CODE%TYPE;
        V_TRANSACTION_REVS                  ACCOUNTING_ENTRY_TYPE.TRANSACTION_REVERSAL%TYPE;
        V_REVENUE_SOURCE                    ACCOUNTING_CODE.REVENUE_SOURCE_CODE%TYPE;
        V_AGENCY_SOURCE                     ACCOUNTING_CODE.AGENCY_SOURCE_CODE%TYPE;
        V_FUND                              FUND.FUND%TYPE;
        V_FUND_DETAIL                       FUND.FUND_DETAIL%TYPE;
        V_CARS_INDEX                        INDEX_CODE.INDEX_CODE%TYPE;
        V_CUST_ID                           INFAR001_OUTBOUND.CUST_ID%TYPE;
        V_DEPOSIT_BU                        INFAR001_OUTBOUND.DEPOSIT_BU%TYPE               := c_FS_DIR_BIZ_UNIT; -- DIR BUSINESS UNIT CODE
        V_DEPOSIT_CNT                       INFAR001_OUTBOUND.DEPOSIT_CNT%TYPE ;                            -- TOTAL DEPOSITS IN THE DATA FILE 
        V_CONTROL_AMT                       INFAR001_OUTBOUND.CONTROL_AMT%TYPE ;                            -- TOTAL DEPOSITS AMOUNT IN THE DATA FILE
        V_TOTAL_AMT                         INFAR001_OUTBOUND.TOTAL_AMT%TYPE;                               -- SUM OF ALL DEPOSITS IN THE DATA FILE    
        V_BANK_CD                           INFAR001_OUTBOUND.BANK_CD%TYPE                  := 'STATE';     -- DEPOSIT BANK CODE
        V_BANK_ACCT_KEY                     INFAR001_OUTBOUND.BANK_ACCT_KEY%TYPE            := '108';       -- DIR BANK ACCOUNT
        V_CONTROL_CURRENCY                  INFAR001_OUTBOUND.CONTROL_CURRENCY%TYPE         := 'USD';       -- DIR TRANSACTION CURRENCY CODE
        V_PAYMENT_AMT                       INFAR001_OUTBOUND.PAYMENT_AMT%TYPE;
        V_DEPOSIT_ID_SEQ                    INFAR001_OUTBOUND.CONTROL_AMT%TYPE;
        V_DEPOSIT_ID                        INFAR001_OUTBOUND.DEPOSIT_ID%TYPE;
        V_PAYMENT_SEQ_NUM                   INFAR001_OUTBOUND.PAYMENT_SEQ_NUM%TYPE;
        V_PAYMENT_ID                        INFAR001_OUTBOUND.PAYMENT_ID%TYPE;
        V_PP_SW                             INFAR001_OUTBOUND.PP_SW%TYPE;                                   -- N = Online applied payments (via payment worksheet or as a miscellaneous receipt payment).
        V_MISC_PAYMENT                      INFAR001_OUTBOUND.MISC_PAYMENT%TYPE;                            -- N = Applied towards invoice
        V_CHECK_DT                          INFAR001_OUTBOUND.CHECK_DT%TYPE;
        V_ZZ_RECEIVED_BY_SCO                INFAR001_OUTBOUND.ZZ_RECEIVED_BY_SCO%TYPE;
        V_ZZ_CASH_TYPE                      INFAR001_OUTBOUND.ZZ_CASH_TYPE%TYPE;                            -- Defaults to GEN if empty
        V_DESCR50_MIXED                     INFAR001_OUTBOUND.DESCR50_MIXED%TYPE;  
        V_DOCUMENT                          INFAR001_OUTBOUND.DOCUMENT%TYPE;
        V_CITY                              INFAR001_OUTBOUND.CITY%TYPE;
        V_COUNTY                            INFAR001_OUTBOUND.COUNTY%TYPE;
        V_TAX_AMT                           INFAR001_OUTBOUND.TAX_AMT%TYPE;
        V_LINE_NOTE_TEXT                    INFAR001_OUTBOUND.LINE_NOTE_TEXT%TYPE;
        V_ID_SEQ_NUM                        INFAR001_OUTBOUND.ID_SEQ_NUM%TYPE               := 1;
        V_REF_QUALIFIER_CODE                INFAR001_OUTBOUND.REF_QUALIFIER_CODE%TYPE;
        V_REF_VALUE                         INFAR001_OUTBOUND.REF_VALUE%TYPE;
        V_DST_SEQ_NUM                       INFAR001_OUTBOUND.DST_SEQ_NUM%TYPE              := 1;
        V_SPEEDCHART_KEY                    INFAR001_OUTBOUND.SPEEDCHART_KEY%TYPE;
        V_MONETARY_AMOUNT                   INFAR001_OUTBOUND.MONETARY_AMOUNT%TYPE;
        V_ACCOUNTING_DT                     INFAR001_OUTBOUND.ACCOUNTING_DT%TYPE;
        V_PI_OFFSET_PAY_ID                  INFAR001_OUTBOUND.PAYMENT_ID%TYPE;
        V_OFFSET_AMT                        INFAR001_OUTBOUND.PAYMENT_ID%TYPE;
        
        
        --LINE 5 Direct Journal Entries Variables
        V_FUND_LGY                          INFAR001_OUTBOUND.FUND%TYPE;
        V_AGENCY_SOURCE_LGY                 INFAR001_OUTBOUND.AGENCY_SOURCE%TYPE;
        V_RESOURCE_TYPE                     INFAR001_OUTBOUND.RESOURCE_TYPE%TYPE;
        V_RESOURCE_CATEGORY                 INFAR001_OUTBOUND.RESOURCE_CATEGORY%TYPE;
        V_RESOURCE_SUB_CAT                  INFAR001_OUTBOUND.RESOURCE_SUB_CAT%TYPE;
        V_ANALYSIS_TYPE                     INFAR001_OUTBOUND.ANALYSIS_TYPE%TYPE;
        V_OPERATING_UNIT                    INFAR001_OUTBOUND.OPERATING_UNIT%TYPE;
        V_PRODUCT                           INFAR001_OUTBOUND.PRODUCT%TYPE;
        V_FUND_CODE                         INFAR001_OUTBOUND.FUND_CODE%TYPE;
        V_CLASS_FLD                         INFAR001_OUTBOUND.CLASS_FLD%TYPE;
        V_PROGRAM_CODE                      INFAR001_OUTBOUND.PROGRAM_CODE%TYPE;
        V_BUDGET_REF                        INFAR001_OUTBOUND.BUDGET_REF%TYPE;
        V_AFFILIATE                         INFAR001_OUTBOUND.AFFILIATE%TYPE;
        V_AFFILIATE_INTRA1                  INFAR001_OUTBOUND.AFFILIATE_INTRA1%TYPE;
        V_AFFILIATE_INTRA2                  INFAR001_OUTBOUND.AFFILIATE_INTRA2%TYPE;
        V_CHARTFIELD1                       INFAR001_OUTBOUND.CHARTFIELD1%TYPE;
        V_CHARTFIELD2                       INFAR001_OUTBOUND.CHARTFIELD2%TYPE;
        V_CHARTFIELD3                       INFAR001_OUTBOUND.CHARTFIELD3%TYPE;
        V_ALTACCT                           INFAR001_OUTBOUND.ALTACCT%TYPE;
        V_DEPTID                            INFAR001_OUTBOUND.DEPTID%TYPE;
        V_FS_FUND                           INFAR001_OUTBOUND.FUND%TYPE;
        V_SUBFUND                           INFAR001_OUTBOUND.SUBFUND%TYPE;
        V_PROGRAM                           INFAR001_OUTBOUND.PROGRAM%TYPE;
        V_ELEMENT                           INFAR001_OUTBOUND.ELEMENT%TYPE;
        V_COMPONENT                         INFAR001_OUTBOUND.COMPONENT%TYPE;
        V_TASK                              INFAR001_OUTBOUND.TASK%TYPE;
        V_PCA                               INFAR001_OUTBOUND.PCA%TYPE;
        V_ORG_CODE                          INFAR001_OUTBOUND.ORG_CODE%TYPE;
        V_INDEX_CODE                        INFAR001_OUTBOUND.INDEX_CODE%TYPE;
        V_OBJECT_DETAIL                     INFAR001_OUTBOUND.OBJECT_DETAIL%TYPE;
        V_AGENCY_OBJECT                     INFAR001_OUTBOUND.AGENCY_OBJECT%TYPE;
        V_SOURCE                            INFAR001_OUTBOUND.SOURCE%TYPE;
        V_GL_ACCOUNT                        INFAR001_OUTBOUND.GL_ACCOUNT%TYPE;
        V_SUBSIDIARY                        INFAR001_OUTBOUND.SUBSIDIARY%TYPE;
        V_FUND_SOURCE                       INFAR001_OUTBOUND.FUND_SOURCE%TYPE;
        V_CHARACTER                         INFAR001_OUTBOUND.CHARACTER%TYPE;
        V_METHOD                            INFAR001_OUTBOUND.METHOD%TYPE;
        V_YEAR                              INFAR001_OUTBOUND.YEAR%TYPE;
        V_REFERENCE                         INFAR001_OUTBOUND.REFERENCE%TYPE;
        V_FFY                               INFAR001_OUTBOUND.FFY%TYPE;
        V_APPROPRIATION_SYMBOL              INFAR001_OUTBOUND.APPROPRIATION_SYMBOL%TYPE;
        V_PROJECT                           INFAR001_OUTBOUND.PROJECT%TYPE;
        V_WORK_PHASE                        INFAR001_OUTBOUND.WORK_PHASE%TYPE;
        V_MULTIPURPOSE                      INFAR001_OUTBOUND.MULTIPURPOSE%TYPE;
        V_LOCATION                          INFAR001_OUTBOUND.LOCATION%TYPE;
        V_DEPT_USE_1                        INFAR001_OUTBOUND.DEPT_USE_1%TYPE;
        V_DEPT_USE_2                        INFAR001_OUTBOUND.DEPT_USE_2%TYPE;
        V_BUDGET_DT                         INFAR001_OUTBOUND.BUDGET_DT%TYPE;
        V_LINE_DESCR                        INFAR001_OUTBOUND.LINE_DESCR%TYPE;
        V_OPEN_ITEM_KEY                     INFAR001_OUTBOUND.OPEN_ITEM_KEY%TYPE;
        V_RECEIVED_DT                       INFAR001_OUTBOUND.RECEIVED_DT%TYPE;
        
        V_DATA_SOURCE_CODE                  INFAR001_OUTBOUND.DATA_SOURCE_CODE%TYPE         := c_CARS_DB;
        V_CREATED_BY                        INFAR001_OUTBOUND.CREATED_BY%TYPE               := c_USER;
        V_CREATED_DATE                      INFAR001_OUTBOUND.CREATED_DATE%TYPE             := SYSDATE;
        V_SUCCESS_FLAG                      VARCHAR2(1)                                     := c_NO;
        V_MESSAGE                           VARCHAR2(500);
        
        --Operating Variables
        V_INFAR001_SUCCESS_FLAG             VARCHAR2(1);
        
        --Cursor to grab deposit level
        CURSOR infar001Deposit_Cursor IS
         SELECT 
            RECEIPT.DEPOSIT_SLIP_NUMBER, 
            TRUNC(RECEIPT.DEPOSIT_DATE) as DEPOSIT_DATE, 
            NVL(RECEIPT.RECEIPT_TYPE_CODE, REVERSE_RECEIPT.RECEIPT_TYPE_CODE) RECEIPT_TYPE_CODE, 
            NVL(RECEIPT.LOCATION_CODE, REVERSE_RECEIPT.LOCATION_CODE)     LOCATION_CODE,
            TRUNC(RECEIPT.DEPOSIT_DATE) as RECEIVED_DT
        FROM ACCOUNTING_ENTRY
            INNER JOIN ACCOUNTING_ENTRY_STATUS
                ON ACCOUNTING_ENTRY.ACCTG_ENTRY_ID      =   ACCOUNTING_ENTRY_STATUS.ACCTG_ENTRY_ID
            INNER JOIN ACCOUNTING_ENTRY_TYPE
                ON ACCOUNTING_ENTRY.ACCTG_ENTRY_TYPE_ID =   ACCOUNTING_ENTRY_TYPE.ACCTG_ENTRY_TYPE_ID
            INNER JOIN ACCOUNTING_CODE
                ON ACCOUNTING_ENTRY.ACCOUNTING_CODE_ID  =   ACCOUNTING_CODE.ACCOUNTING_CODE_ID
            INNER JOIN FUND_ALLOCATION
                ON ACCOUNTING_CODE.FUND_ALLOCATION_ID   =   FUND_ALLOCATION.FUND_ALLOCATION_ID
            INNER JOIN FUND
                ON FUND.FUND_ID                         =   FUND_ALLOCATION.FUND_TO_ID
            INNER JOIN FISCAL_PERIOD
                ON FISCAL_PERIOD.FISCAL_PERIOD_ID       =   FUND.FISCAL_PERIOD_ID
            INNER JOIN ACCTG_TRANSACT_EVENT_ASSOC
                ON ACCOUNTING_ENTRY.ACCTG_TRANSACTION_ID =  ACCTG_TRANSACT_EVENT_ASSOC.ACCTG_TRANSACTION_ID
            INNER JOIN EVENT
                ON ACCTG_TRANSACT_EVENT_ASSOC.EVENT_ID  =   EVENT.EVENT_ID
            INNER JOIN EVENT_TYPE
                ON EVENT_TYPE.EVENT_TYPE_ID             =   EVENT.EVENT_TYPE_ID
            INNER JOIN PARTICIPANT_ROLE
                ON EVENT.EVENT_ID                       =   PARTICIPANT_ROLE.EVENT_ID
            INNER JOIN RECEIPT
                ON ACCOUNTING_ENTRY.ACCTG_TRANSACTION_ID =  RECEIPT.ACCTG_TRANSACTION_ID
            LEFT OUTER JOIN EVENT_ASSOCIATION
                ON EVENT_ASSOCIATION.EVENT_TO_ID        =   EVENT.EVENT_ID
            LEFT OUTER JOIN EVENT REVERSE_EVENT
                ON REVERSE_EVENT.EVENT_ID               =   EVENT_ASSOCIATION.EVENT_FROM_ID
            LEFT OUTER JOIN ACCTG_TRANSACT_EVENT_ASSOC REVERSE_ATEA
                ON REVERSE_EVENT.EVENT_ID               =   REVERSE_ATEA.EVENT_ID
            LEFT OUTER JOIN RECEIPT REVERSE_RECEIPT
                ON REVERSE_ATEA.ACCTG_TRANSACTION_ID    =   REVERSE_RECEIPT.ACCTG_TRANSACTION_ID
        WHERE ACCOUNTING_ENTRY_STATUS.FS_PROCESS_STATUS = c_STATUS_SELECTED
          AND EVENT_TYPE.PROGRAM_UNIT_CODE              = P_PROGRAM_UNIT
          AND ACCOUNTING_ENTRY_TYPE.TRANSACTION_REVERSAL= P_TRANSACT_REVS
        GROUP BY RECEIPT.DEPOSIT_SLIP_NUMBER, 
                trunc(RECEIPT.DEPOSIT_DATE), 
                NVL(RECEIPT.RECEIPT_TYPE_CODE, REVERSE_RECEIPT.RECEIPT_TYPE_CODE), 
                NVL(RECEIPT.LOCATION_CODE, REVERSE_RECEIPT.LOCATION_CODE)
        ORDER BY RECEIPT.DEPOSIT_SLIP_NUMBER;
            
       --Cursor to gather Infar001 selected for processing
       CURSOR infar001Data_Cursor IS
         SELECT ACCOUNTING_ENTRY.ACCTG_ENTRY_ID,
                ACCOUNTING_ENTRY.ACCTG_TRANSACTION_ID,
                EVENT.AR_ROOT_DOCUMENT,
                CASE WHEN ACCOUNTING_ENTRY_TYPE.TRANSACTION_REVERSAL = c_NOT_REVERSE THEN
                    ACCOUNTING_ENTRY.AMOUNT
                WHEN ACCOUNTING_ENTRY_TYPE.TRANSACTION_REVERSAL      = c_REVERSE THEN
                    ACCOUNTING_ENTRY.AMOUNT * -1
                END AMOUNT,
                EVENT.EVENT_DATE,
                EVENT.CREATED_DATE,
                RECEIPT.DEPOSIT_DATE,
                RECEIPT.RECEIPT_DATE,
                RECEIPT.BILL_TYPE_CODE,
                RECEIPT.LOCATION_CODE,
                RECEIPT.RECEIPT_CONTROL_NUMBER,
                GET_FS_CUSTOMER_ID (EVENT.AR_ROOT_DOCUMENT) AS CUST_ID,
                ACCOUNTING_ENTRY_TYPE.ACCTG_TRANSACT_CODE,
                ACCOUNTING_ENTRY_TYPE.TRANSACTION_REVERSAL,
                ACCOUNTING_CODE.REVENUE_SOURCE_CODE,
                ACCOUNTING_CODE.AGENCY_SOURCE_CODE,
                ACCOUNTING_CODE.INDEX_CODE,
                FISCAL_PERIOD.FISCAL_YEAR_NAME,
                FUND.FUND,
                FUND.FUND_DETAIL
            FROM ACCOUNTING_ENTRY
                INNER JOIN ACCOUNTING_ENTRY_STATUS
                    ON ACCOUNTING_ENTRY.ACCTG_ENTRY_ID      =   ACCOUNTING_ENTRY_STATUS.ACCTG_ENTRY_ID
                INNER JOIN ACCOUNTING_ENTRY_TYPE
                    ON ACCOUNTING_ENTRY.ACCTG_ENTRY_TYPE_ID =   ACCOUNTING_ENTRY_TYPE.ACCTG_ENTRY_TYPE_ID
                INNER JOIN ACCOUNTING_CODE
                    ON ACCOUNTING_ENTRY.ACCOUNTING_CODE_ID  =   ACCOUNTING_CODE.ACCOUNTING_CODE_ID
                INNER JOIN FUND_ALLOCATION
                    ON ACCOUNTING_CODE.FUND_ALLOCATION_ID   =   FUND_ALLOCATION.FUND_ALLOCATION_ID
                INNER JOIN FUND
                    ON FUND.FUND_ID                         =   FUND_ALLOCATION.FUND_TO_ID
                INNER JOIN FISCAL_PERIOD
                    ON FISCAL_PERIOD.FISCAL_PERIOD_ID       =   FUND.FISCAL_PERIOD_ID
                INNER JOIN ACCTG_TRANSACT_EVENT_ASSOC
                    ON ACCOUNTING_ENTRY.ACCTG_TRANSACTION_ID=   ACCTG_TRANSACT_EVENT_ASSOC.ACCTG_TRANSACTION_ID
                INNER JOIN EVENT
                    ON ACCTG_TRANSACT_EVENT_ASSOC.EVENT_ID  =   EVENT.EVENT_ID
                INNER JOIN EVENT_TYPE
                    ON EVENT_TYPE.EVENT_TYPE_ID             =   EVENT.EVENT_TYPE_ID
                INNER JOIN PARTICIPANT_ROLE
                    ON EVENT.EVENT_ID                       =   PARTICIPANT_ROLE.EVENT_ID
                INNER JOIN RECEIPT
                    ON ACCOUNTING_ENTRY.ACCTG_TRANSACTION_ID=   RECEIPT.ACCTG_TRANSACTION_ID
                LEFT OUTER JOIN EVENT_ASSOCIATION
                    ON EVENT_ASSOCIATION.EVENT_TO_ID        =   EVENT.EVENT_ID
                LEFT OUTER JOIN EVENT REVERSE_EVENT
                    ON REVERSE_EVENT.EVENT_ID               =   EVENT_ASSOCIATION.EVENT_FROM_ID
                LEFT OUTER JOIN ACCTG_TRANSACT_EVENT_ASSOC REVERSE_ATEA
                    ON REVERSE_EVENT.EVENT_ID               =   REVERSE_ATEA.EVENT_ID
                LEFT OUTER JOIN RECEIPT REVERSE_RECEIPT
                    ON REVERSE_ATEA.ACCTG_TRANSACTION_ID    =   REVERSE_RECEIPT.ACCTG_TRANSACTION_ID
            WHERE ACCOUNTING_ENTRY_STATUS.FS_PROCESS_STATUS = c_STATUS_SELECTED
              AND NVL(REVERSE_RECEIPT.RECEIPT_TYPE_CODE, RECEIPT.RECEIPT_TYPE_CODE) 
                                                            = V_RECEIPT_TYPE_CODE
              AND RECEIPT.DEPOSIT_SLIP_NUMBER               = V_DEPOSIT_SLIP
              AND trunc(RECEIPT.DEPOSIT_DATE)               = V_DEPOSIT_DATE
              AND EVENT_TYPE.PROGRAM_UNIT_CODE              = P_PROGRAM_UNIT
              AND ACCOUNTING_ENTRY_TYPE.TRANSACTION_REVERSAL= P_TRANSACT_REVS
              AND RECEIPT.LOCATION_CODE                     = V_LOCATION_CODE
            ORDER BY EVENT.AR_ROOT_DOCUMENT ASC, 
                     ACCOUNTING_ENTRY_TYPE.ACCTG_TRANSACT_CODE  ASC, 
                     ACCOUNTING_ENTRY_TYPE.TRANSACTION_REVERSAL ASC;
                
       --Cursor to gather AES Status to update
       CURSOR infar001selected_Cursor IS
        SELECT ACCOUNTING_ENTRY.ACCTG_ENTRY_ID 
                 FROM ACCOUNTING_ENTRY
                    INNER JOIN ACCOUNTING_ENTRY_STATUS
                        ON ACCOUNTING_ENTRY.ACCTG_ENTRY_ID      =   ACCOUNTING_ENTRY_STATUS.ACCTG_ENTRY_ID
                    INNER JOIN ACCOUNTING_ENTRY_TYPE 
                        ON ACCOUNTING_ENTRY.ACCTG_ENTRY_TYPE_ID =   ACCOUNTING_ENTRY_TYPE.ACCTG_ENTRY_TYPE_ID
                    INNER JOIN ACCTG_TRANSACT_EVENT_ASSOC
                        ON ACCOUNTING_ENTRY.ACCTG_TRANSACTION_ID=   ACCTG_TRANSACT_EVENT_ASSOC.ACCTG_TRANSACTION_ID
                    INNER JOIN EVENT
                        ON ACCTG_TRANSACT_EVENT_ASSOC.EVENT_ID  =   EVENT.EVENT_ID
                    INNER JOIN EVENT_TYPE
                        ON EVENT_TYPE.EVENT_TYPE_ID             =   EVENT.EVENT_TYPE_ID
                 WHERE ACCOUNTING_ENTRY_TYPE.TRANSACTION_REVERSAL   = P_TRANSACT_REVS
                   AND ACCOUNTING_ENTRY.AMOUNT                      <> 0
                   AND ACCOUNTING_ENTRY_TYPE.ACCTG_TRANSACT_CODE    = P_TRANSACT_CODE
                   AND EVENT_TYPE.PROGRAM_UNIT_CODE                 = P_PROGRAM_UNIT
                   AND ACCOUNTING_ENTRY_STATUS.FS_PROCESS_STATUS    = c_STATUS_NEW;
            
    BEGIN
        DBMS_OUTPUT.PUT_LINE('**** Begin GET_INFAR001_DATA ****');
        DBMS_OUTPUT.PUT_LINE( P_BATCH_ID ||' '|| P_BATCH_DATE || ' ' ||P_PROGRAM_UNIT || ' '|| P_TRANSACT_CODE || ' ' || P_TRANSACT_REVS);
               
        --Set current date into Accounting_Dt field
        V_ACCOUNTING_DT := TO_DATE(TO_CHAR(V_CREATED_DATE, 'MMDDYYYY'), 'MM/DD/YYYY');

        V_TRANSACTION_CNT := 0; 
        
        --Gathers Data to be processed for INFAR001
        OPEN infar001selected_Cursor;
        LOOP
            FETCH infar001selected_Cursor into V_ACCTG_ENTRY_ID;
            EXIT WHEN infar001selected_Cursor%NOTFOUND; 
            
            V_TRANSACTION_CNT := V_TRANSACTION_CNT + 1;
            
            --Update Statuses to Selected
            DBMS_OUTPUT.PUT_LINE('infar001selected_Cursor: '||V_ACCTG_ENTRY_ID|| ' row = '||V_TRANSACTION_CNT);
            
            UPDATE_STATUS_BY_ID(c_STATUS_SELECTED, SYSDATE, V_ACCTG_ENTRY_ID);
            
            DBMS_OUTPUT.PUT_LINE('Update Accounting Entry Status record status set to Selected: '||V_ACCTG_ENTRY_ID);
            
        END LOOP;
        CLOSE infar001selected_Cursor;
        
        IF V_TRANSACTION_CNT = 0  THEN
            RETURN;
        END IF;
        
        --    This calls running function
        GET_INFAR001_COUNTER_DATA(P_BATCH_ID, P_PROGRAM_UNIT,V_DATA_SOURCE_CODE, V_CONTROL_AMT, c_EMPTY_COUNTER, V_SUCCESS_FLAG, V_MESSAGE);
                
        DBMS_OUTPUT.PUT_LINE('GET_INFAR001_COUNTER_DATA completed: '||V_SUCCESS_FLAG);      
        
        --Loop through Deposit Cursor for both reversals and payments.Deposit Cursor groups by Deposit
        
        OPEN infar001Deposit_Cursor; 
        LOOP
            FETCH infar001Deposit_Cursor into V_DEPOSIT_SLIP, V_DEPOSIT_DATE,V_RECEIPT_TYPE_CODE, V_LOCATION_CODE, V_RECEIVED_DT;
            EXIT WHEN infar001Deposit_Cursor%NOTFOUND; 

            --Reset INFAR001 Counter Data pass in parameters
            --Call INFAR001 Counter for Deposit 001 line, will generate deposit id seq
            
            DBMS_OUTPUT.PUT_LINE(  'P_TRANSACT_REVS: ' ||P_TRANSACT_REVS|| ' V_DEPOSIT_SLIP: '      ||V_DEPOSIT_SLIP 
                                    || ' V_DEPOSIT_DATE: ' || V_DEPOSIT_DATE|| ' V_RECEIPT_TYPE_CODE: ' || V_RECEIPT_TYPE_CODE
                                    || ' V_LOCATION_CODE: '||V_LOCATION_CODE|| ' V_RECEIVED_DT: '       ||V_RECEIVED_DT);
            
            GET_INFAR001_COUNTER_DATA(P_BATCH_ID, P_PROGRAM_UNIT, V_DATA_SOURCE_CODE, 0, c_DC_ROW_ID, V_SUCCESS_FLAG, V_MESSAGE);
               
            --Assign Deposit Id from counter
            V_DEPOSIT_ID := FS_INTERFACE_PKG.V_INFAR001_COUNT_REC.DEPOSIT_ID;
            
            --Get FS Deposit Number from function
            V_FS_DEPOSIT := FUNC_GET_FS_DEPOSIT (P_PROGRAM_UNIT,V_DEPOSIT_DATE,V_DEPOSIT_SLIP, V_DEPOSIT_DATE,V_RECEIPT_TYPE_CODE);
                    
            --Get FS Payment Method from function
            V_FS_PAYMENT_METHOD := FUNC_GET_FS_PAYMENT_METHOD (V_RECEIPT_TYPE_CODE);
            
            --Get FS Deposit Type from function
            V_FS_DEPOSIT_TYPE := FUNC_GET_FS_DEPOSIT_TYPE (V_RECEIPT_TYPE_CODE);
            
            DBMS_OUTPUT.PUT_LINE('V_DEPOSIT_ID: '           || V_DEPOSIT_ID 
                                    || ' V_RECEIPT_TYPE_CODE:'  || V_RECEIPT_TYPE_CODE
                                    || ' V_FS_DEPOSIT: '        || V_FS_DEPOSIT
                                    || ' V_FS_PAYMENT_METHOD: ' || V_FS_PAYMENT_METHOD
                                    || ' V_FS_DEPOSIT_TYPE: '   || V_FS_DEPOSIT_TYPE);
            
            --ZZ Bank Deposit Number = FS deposit #
            IF V_FS_DEPOSIT_TYPE = 'R' 
                THEN V_ZZ_LEG_DEP_ID := V_FS_DEPOSIT;
            ELSE V_ZZ_BNK_DEPOSIT_NUM := V_FS_DEPOSIT;
            END IF;
            
            
            --ZZ Identifier = Location Code
            V_ZZ_IDENTIFIER := V_LOCATION_CODE;
            
            --Check mandatory fields before inserting deposit level 001 records
            IF      V_FS_DEPOSIT IS NOT NULL 
                AND V_FS_PAYMENT_METHOD IS NOT NULL
                AND V_FS_DEPOSIT_TYPE IS NOT NULL
                AND V_ZZ_IDENTIFIER IS NOT NULL
                
            THEN V_INFAR001_SUCCESS_FLAG := 'Y';
            
            ELSE V_INFAR001_SUCCESS_FLAG := 'N';
            
            END IF;
            
            
            --Insert Header line 1
            --V_ACCTG_ENTRY_ID, 5/24/2018: Vinay Patil: Issue reported by Raman N that their can more than one Accounting Entry Id for deposit. Therefore populating null value instead. 
            IF V_INFAR001_SUCCESS_FLAG = 'Y'
                THEN
                    INSERT_INFAR001_DATA(
                        P_BATCH_ID,             P_BATCH_DATE,   P_PROGRAM_UNIT,     V_DEPOSIT_BU,       V_DEPOSIT_ID,   
                        V_ACCOUNTING_DT,        V_BANK_CD,      V_BANK_ACCT_KEY,    V_FS_DEPOSIT_TYPE,  V_CONTROL_CURRENCY,
                        V_ZZ_BNK_DEPOSIT_NUM,   V_ZZ_IDENTIFIER,0,                  1,                  V_RECEIVED_DT,  
                        V_TOTAL_CHECKS,         V_FLAG,         V_BANK_OPER_NUM,    V_ZZ_LEG_DEP_ID,    NULL,               
                        V_SUCCESS_FLAG,         V_MESSAGE
                        );
                    
                DBMS_OUTPUT.PUT_LINE('AFTER INSERT_INFAR001_DATA SUCCESS FLAG'||V_SUCCESS_FLAg||' MESSAGE '||V_MESSAGE);
            END IF;
            
                --Loop through Individual Payment Rows, insert payment data
            OPEN infar001Data_Cursor;
            LOOP
                FETCH infar001Data_Cursor into 
                    V_ACCTG_ENTRY_ID, 
                    V_ACCTG_TRANS_ID, 
                    V_ROOT_DOCUMENT, 
                    V_ACCTG_ENTRY_AMT, 
                    V_EVENT_DATE, 
                    V_RECEIVED_DT, 
                    V_DEPOSIT_DATE, 
                    V_RECEIPT_DATE, 
                    V_BILL_TYPE_CODE, 
                    V_LOCATION_CODE, 
                    V_REPT_CON_NUM,
                    V_CUST_ID, 
                    V_TRANSACTION_CODE, 
                    V_TRANSACTION_REVS, 
                    V_REVENUE_SOURCE, 
                    V_AGENCY_SOURCE, 
                    V_CARS_INDEX, 
                    V_FISCAL_YEAR_NAME, 
                    V_FUND, 
                    V_FUND_DETAIL
                    ;
                
                    DBMS_OUTPUT.PUT_LINE('infar001Data_Cursor STARTED');
                EXIT WHEN infar001Data_Cursor%NOTFOUND;
                
                --TODO Check null mandatory fields, log and don't process all records of invoice tbd future
                --IS THIS BEING DEVELOPED?
                IF V_INFAR001_SUCCESS_FLAG = 'N'
                    THEN GOTO INFAR001_DATA_ERROR;
                 END IF;
                
                
                --default value
                V_REF_QUALIFIER_CODE := 'I'; 
                
                --Alt Account is concatenation of revenue source and agency source
                V_ALTACCT := V_REVENUE_SOURCE || V_AGENCY_SOURCE;
                
                --Recording Payment Id as Receipt Control Number
                V_PAYMENT_ID := V_REPT_CON_NUM;
                
                --CARS Not Currently Recording Check Date
                V_CHECK_DT := NULL;
                
                --Ref Value is ar root document
                V_REF_VALUE := GET_FS_LINE_NUMBER(V_ROOT_DOCUMENT, P_PROGRAM_UNIT);
                
                --Prep Data for Inserts. Line Note Text = Bill Type Code + Invoice Number
                V_LINE_NOTE_TEXT := V_BILL_TYPE_CODE || ' ' || V_ROOT_DOCUMENT;
                
                --Product is fiscal year for TC 101 and max is prior year
                -- 5/25/2018, Vinay Patil: For 142 use the Fiscal Year fetched in the infar001Data_Cursor
                
                IF (V_TRANSACTION_CODE = c_TC_101 ) THEN
                
                    V_PRODUCT := FUNC_GET_PRIOR_FISCAL_YEAR(V_ROOT_DOCUMENT);
                
                ELSIF (V_TRANSACTION_CODE = c_TC_142 ) THEN
                
                    V_PRODUCT := V_FISCAL_YEAR_NAME;                
                END IF;
                
                --Only fill in Chartfield1 if there is a fund detail
                IF V_FUND_DETAIL IS NOT NULL THEN
                     V_CHARTFIELD1 := V_FUND || V_FUND_DETAIL;
                ELSE 
                    V_CHARTFIELD1 := '';
                END IF;
                        
                --Fiscal Index = concatenation of BU + Index Code
                V_DEPTID := V_DEPOSIT_BU || V_CARS_INDEX;
                   
                DBMS_OUTPUT.PUT_LINE(  'V_REF_QUALIFIER_CODE: ' || V_REF_QUALIFIER_CODE 
                                        || ' V_ALTACCT: '           || V_ALTACCT    || ' V_PAYMENT_ID: '    || V_PAYMENT_ID
                                        || ' V_CHECK_DT: '          ||V_CHECK_DT    || ' V_REF_VALUE: '     ||V_REF_VALUE   || ' V_PRODUCT: '||V_PRODUCT
                                        || ' V_CHARTFIELD1: '       ||V_CHARTFIELD1 || ' V_DEPTID: '        ||V_DEPTID);
                
                --Billed Payments
                IF V_TRANSACTION_CODE = c_TC_142 THEN
                    
                    DBMS_OUTPUT.PUT_LINE('**** Insert TC 142 Row **** ' || V_PROGRAM_UNIT_CODE || ' ' || V_ROOT_DOCUMENT);
                    
                    --Prep Data for Billed Entries
                    --For Billed payments, miscellaneous payment misc_payment = 'N' No and  payment predictor pp_sw = 'Y' Yes
                    V_MISC_PAYMENT  := c_NO;
                    
                    IF V_TRANSACTION_REVS = c_REVERSE THEN
                        V_PP_SW         := c_NO;
                    ELSIF V_TRANSACTION_REVS = c_NO THEN
                        V_PP_SW         := FUNC_GET_BILLED_PP_SW(P_PROGRAM_UNIT);
                    END IF;
                    
                    --Billed Entries, Reversal negative, Regular positive
                    IF V_TRANSACTION_REVS = c_REVERSE THEN
                        
                        V_PAYMENT_AMT := V_ACCTG_ENTRY_AMT * -1;  -- Negative
                
                    ELSIF V_TRANSACTION_REVS = c_NO THEN
                        
                        V_PAYMENT_AMT := V_ACCTG_ENTRY_AMT;
                
                    END IF;
                    
                    --Insert Rows for Billed Entries
                    GET_INFAR001_COUNTER_DATA(P_BATCH_ID, P_PROGRAM_UNIT, V_DATA_SOURCE_CODE, V_ACCTG_ENTRY_AMT, c_PI_ROW_ID , V_SUCCESS_FLAG, V_MESSAGE);
                    
                    --Set PAYMENT_SEQ_NUM
                    V_PAYMENT_SEQ_NUM := FS_INTERFACE_PKG.V_INFAR001_COUNT_REC.PAYMENT_SEQ_NUM;
                    
                    DBMS_OUTPUT.PUT_LINE('V_MISC_PAYMENT: '||V_MISC_PAYMENT || ' V_PAYMENT_AMT: ' 
                                            || V_PAYMENT_AMT|| ' V_PAYMENT_SEQ_NUM: '|| V_PAYMENT_SEQ_NUM);
                    
                    --line 2
                    INSERT_INFAR001_DATA(P_BATCH_ID,      P_BATCH_DATE,   P_PROGRAM_UNIT,     V_DEPOSIT_BU,           V_DEPOSIT_ID,   V_PAYMENT_SEQ_NUM,
                                        V_PAYMENT_ID,     V_ACCOUNTING_DT,V_ACCTG_ENTRY_AMT,  V_CONTROL_CURRENCY,     V_PP_SW,
                                        V_MISC_PAYMENT,   V_CHECK_DT,     V_FS_PAYMENT_METHOD,V_ZZ_RECEIVED_BY_SCO,   V_ZZ_CASH_TYPE,
                                        V_DESCR50_MIXED,  V_DOCUMENT,     V_CITY,             V_COUNTY,               V_TAX_AMT,      V_LINE_NOTE_TEXT, 
                                        V_ACCTG_ENTRY_ID, V_ROOT_DOCUMENT,V_SUCCESS_FLAG,     V_MESSAGE
                                        );
                    
                    GET_INFAR001_COUNTER_DATA(P_BATCH_ID, P_PROGRAM_UNIT, V_DATA_SOURCE_CODE, V_ACCTG_ENTRY_AMT, c_IR_ROW_ID, V_SUCCESS_FLAG, V_MESSAGE);
                    
                    DBMS_OUTPUT.PUT_LINE('GET_INFAR001_COUNTER_DATA COMPLETED FOR LINE 2');
                    
                    --line 3
                    INSERT_INFAR001_DATA(
                                        P_BATCH_ID,     P_BATCH_DATE,           P_PROGRAM_UNIT,     V_DEPOSIT_BU,       V_DEPOSIT_ID,   V_PAYMENT_SEQ_NUM,
                                        V_ID_SEQ_NUM,   V_REF_QUALIFIER_CODE,   V_REF_VALUE,        V_ACCTG_ENTRY_ID,   V_ROOT_DOCUMENT,V_SUCCESS_FLAG, 
                                        V_MESSAGE
                                        );
                    
                    DBMS_OUTPUT.PUT_LINE('GET_INFAR001_COUNTER_DATA COMPLETED FOR LINE 3')
                    ;
                    --line 4
                    INSERT_INFAR001_DATA(
                                        P_BATCH_ID,     P_BATCH_DATE,   P_PROGRAM_UNIT,     V_DEPOSIT_BU,   V_DEPOSIT_ID,   V_PAYMENT_SEQ_NUM,
                                        V_ID_SEQ_NUM,   V_CUST_ID,      V_ACCTG_ENTRY_ID,   V_ROOT_DOCUMENT,V_SUCCESS_FLAG, V_MESSAGE
                                        );
                        
                    DBMS_OUTPUT.PUT_LINE('GET_INFAR001_COUNTER_DATA COMPLETED FOR LINE 4');
                    
                ELSIF V_TRANSACTION_CODE = c_TC_101 THEN
                
                    DBMS_OUTPUT.PUT_LINE('**** Insert TC 101 Row **** ' || V_PROGRAM_UNIT_CODE || ' ' || V_ROOT_DOCUMENT);
                    
                    --Prep data for Direct Journal Entries
                    --For Unbilled payments, miscellaneous payment misc_payment = 'Y' Yes and  payment predictor pp_sw = 'N' No
                    V_MISC_PAYMENT  := c_YES;
                    V_PP_SW         := c_NO;
                    
                    --Direct Journal Payment Reversals Amt Positive, Regular Negative amount
                    IF V_TRANSACTION_REVS = c_REVERSE THEN
                    
                        V_PAYMENT_AMT       := V_ACCTG_ENTRY_AMT * 1;
                        V_MONETARY_AMOUNT   := V_ACCTG_ENTRY_AMT * -1;
                    
                    ELSIF V_TRANSACTION_REVS = c_NO THEN
                     
                       V_PAYMENT_AMT        := V_ACCTG_ENTRY_AMT;
                       V_MONETARY_AMOUNT    := V_ACCTG_ENTRY_AMT * -1;
                    
                    END IF;
                    
                    --Insert Rows for Direct Journal Entries
                    GET_INFAR001_COUNTER_DATA(P_BATCH_ID, P_PROGRAM_UNIT, V_DATA_SOURCE_CODE, V_ACCTG_ENTRY_AMT, c_PI_ROW_ID, V_SUCCESS_FLAG, V_MESSAGE);
                    
                    --Set PAYMENT_SEQ_NUM
                    V_PAYMENT_SEQ_NUM := FS_INTERFACE_PKG.V_INFAR001_COUNT_REC.PAYMENT_SEQ_NUM;
                        
                    --line 2 UNBILLED
                    INSERT_INFAR001_DATA(P_BATCH_ID,        P_BATCH_DATE,   P_PROGRAM_UNIT,     V_DEPOSIT_BU,           V_DEPOSIT_ID,   V_PAYMENT_SEQ_NUM,
                                        V_PAYMENT_ID,       V_ACCOUNTING_DT,V_ACCTG_ENTRY_AMT,  V_CONTROL_CURRENCY,     V_PP_SW,
                                        V_MISC_PAYMENT,     V_CHECK_DT,     V_FS_PAYMENT_METHOD,V_ZZ_RECEIVED_BY_SCO,   V_ZZ_CASH_TYPE,
                                        V_DESCR50_MIXED,    V_DOCUMENT,     V_CITY,             V_COUNTY,               V_TAX_AMT,      V_LINE_NOTE_TEXT, 
                                        V_ACCTG_ENTRY_ID,   V_ROOT_DOCUMENT,V_SUCCESS_FLAG,     V_MESSAGE
                                        );
                    
                    --line 4
                    INSERT_INFAR001_DATA(
                                        P_BATCH_ID,     P_BATCH_DATE,   P_PROGRAM_UNIT,     V_DEPOSIT_BU,   V_DEPOSIT_ID,   V_PAYMENT_SEQ_NUM,
                                        V_ID_SEQ_NUM,   V_CUST_ID,      V_ACCTG_ENTRY_ID,   V_ROOT_DOCUMENT,V_SUCCESS_FLAG, V_MESSAGE
                                        );
                        
                    GET_INFAR001_COUNTER_DATA(P_BATCH_ID, P_PROGRAM_UNIT,V_DATA_SOURCE_CODE, V_ACCTG_ENTRY_AMT, c_CI_ROW_ID, V_SUCCESS_FLAG, V_MESSAGE);
                        
                    V_DST_SEQ_NUM := FS_INTERFACE_PKG.V_INFAR001_COUNT_REC.DST_SEQ_NUM;
                    
                    --line 5
                    INSERT_INFAR001_DATA(P_BATCH_ID,        P_BATCH_DATE,   P_PROGRAM_UNIT,     V_DEPOSIT_BU,       V_DEPOSIT_ID,       
                                        V_PAYMENT_SEQ_NUM,  V_DST_SEQ_NUM,  V_DEPOSIT_BU,       V_SPEEDCHART_KEY,   V_MONETARY_AMOUNT,  
                                        V_REVENUE_SOURCE,   V_RESOURCE_TYPE,V_RESOURCE_CATEGORY,V_RESOURCE_SUB_CAT, V_ANALYSIS_TYPE, 
                                        V_OPERATING_UNIT,   V_PRODUCT,      V_FUND,             V_CLASS_FLD,        V_PROGRAM_CODE, 
                                        V_BUDGET_REF,       V_AFFILIATE,    V_AFFILIATE_INTRA1, V_AFFILIATE_INTRA2, V_CHARTFIELD1,
                                        V_CHARTFIELD2,      V_CHARTFIELD3,  V_ALTACCT, V_DEPTID,V_FUND_LGY,         V_SUBFUND, 
                                        V_PROGRAM,          V_ELEMENT,      V_COMPONENT,        V_TASK,             V_PCA, 
                                        V_ORG_CODE,         V_INDEX_CODE,   V_OBJECT_DETAIL,    V_AGENCY_OBJECT,    V_SOURCE, 
                                        V_AGENCY_SOURCE_LGY,V_GL_ACCOUNT,   V_SUBSIDIARY,       V_FUND_SOURCE,      V_CHARACTER,
                                        V_METHOD,           V_YEAR,         V_REFERENCE,        V_FFY,              V_APPROPRIATION_SYMBOL, 
                                        V_PROJECT,          V_WORK_PHASE,   V_MULTIPURPOSE,     V_LOCATION,         V_DEPT_USE_1, 
                                        V_DEPT_USE_2,       V_BUDGET_DT,    V_LINE_DESCR,       V_OPEN_ITEM_KEY,    V_ACCTG_ENTRY_ID, 
                                        V_ROOT_DOCUMENT,    V_SUCCESS_FLAG, V_MESSAGE
                                        );
                    
                END IF;
                
                --UPDATE ACCOUNTING_ENTRY_STATUS to BATCHED
                DBMS_OUTPUT.PUT_LINE('Before UPDATE_STATUS_BY_ID: ' || V_ACCTG_ENTRY_ID||' AR root document '|| V_ROOT_DOCUMENT);
                
                UPDATE_STATUS_BY_ID(c_STATUS_BATCHED , SYSDATE, V_ACCTG_ENTRY_ID);
                
                DBMS_OUTPUT.PUT_LINE('After UPDATE_STATUS_BY_ID: ' || V_ACCTG_ENTRY_ID);
                
                --Insert Error Log in case of null mandatory fields at the deposit level
                <<INFAR001_DATA_ERROR>> 
                
                IF V_INFAR001_SUCCESS_FLAG = 'N'
                    THEN 
                    LOG_CARS_ERROR(
                        p_errorLevel    => '4',
                        p_severity      => c_HIGH_SEVERITY,
                        p_errorDetail   => 'FISCAL INSERT_INFAR001_DATA procedure did not succeed for ' ||
                                            V_ROOT_DOCUMENT || ' For: ' ||
                                            V_ACCTG_ENTRY_AMT,
                        p_errorCode     => '5002',
                        p_errorMessage  => 'INFAR001 Data Failure',
                        p_dataSource    => c_CARS_DB);
                        
                    UPDATE_STATUS_BY_ID(c_STATUS_FAILED , SYSDATE, V_ACCTG_ENTRY_ID);
                 END IF;
    				
            END LOOP;
            CLOSE infar001Data_Cursor;
            
            select MAX(A.CONTROL_AMT) INTO V_ACCTG_ENTRY_AMT
            from TABLE (FS_INTERFACE_PKG.V_INFAR001_TBL) A  
            WHERE   A.RECORD_ID IN 
                (SELECT MAX(B.RECORD_ID) FROM TABLE (FS_INTERFACE_PKG.V_INFAR001_TBL) B GROUP BY B.DEPOSIT_ID)
            ;
            
            --Insert Rows for Direct Journal Entries
            GET_INFAR001_COUNTER_DATA(P_BATCH_ID, P_PROGRAM_UNIT, V_DATA_SOURCE_CODE, V_ACCTG_ENTRY_AMT * -1, c_PI_ROW_ID, V_SUCCESS_FLAG, V_MESSAGE);
            
            --Set PAYMENT_SEQ_NUM
            V_PAYMENT_SEQ_NUM := FS_INTERFACE_PKG.V_INFAR001_COUNT_REC.PAYMENT_SEQ_NUM;
            
            V_PI_OFFSET_PAY_ID := V_DEPOSIT_ID || 'OFFSET';
            
            V_OFFSET_AMT := V_ACCTG_ENTRY_AMT * -1;
            
            V_FS_PAYMENT_METHOD := 'OFF';
            
            V_LINE_NOTE_TEXT := 'DIR workaround to record deposits. ' || V_DEPOSIT_ID || 'OFFSET';
            
            --line 2 UNBILLED
            INSERT_INFAR001_DATA(       P_BATCH_ID,         P_BATCH_DATE,       P_PROGRAM_UNIT,     V_DEPOSIT_BU,           
                V_DEPOSIT_ID,           V_PAYMENT_SEQ_NUM,  V_PI_OFFSET_PAY_ID, V_ACCOUNTING_DT,    V_OFFSET_AMT,  
                V_CONTROL_CURRENCY,     V_PP_SW,            V_MISC_PAYMENT,     V_CHECK_DT,         V_FS_PAYMENT_METHOD,
                V_ZZ_RECEIVED_BY_SCO,   V_ZZ_CASH_TYPE,     V_DESCR50_MIXED,    V_DOCUMENT,         V_CITY,             
                V_COUNTY,               V_TAX_AMT,          V_LINE_NOTE_TEXT,   V_ACCTG_ENTRY_ID,   V_ROOT_DOCUMENT,
                V_SUCCESS_FLAG,         V_MESSAGE
                );
            
            GET_INFAR001_COUNTER_DATA(P_BATCH_ID, P_PROGRAM_UNIT,V_DATA_SOURCE_CODE, V_ACCTG_ENTRY_AMT, c_CI_ROW_ID, V_SUCCESS_FLAG, V_MESSAGE);
                
            V_DST_SEQ_NUM := FS_INTERFACE_PKG.V_INFAR001_COUNT_REC.DST_SEQ_NUM;
            
            V_MONETARY_AMOUNT := V_ACCTG_ENTRY_AMT;
            
            V_REVENUE_SOURCE := '2090100';
            
            V_FUND := '000000108';
            
            V_ALTACCT := '0000000000';
            
            --line 5
            INSERT_INFAR001_DATA(P_BATCH_ID,        P_BATCH_DATE,   P_PROGRAM_UNIT,     V_DEPOSIT_BU,       V_DEPOSIT_ID,       
                V_PAYMENT_SEQ_NUM,  V_DST_SEQ_NUM,  V_DEPOSIT_BU,       V_SPEEDCHART_KEY,   V_MONETARY_AMOUNT,  
                V_REVENUE_SOURCE,   V_RESOURCE_TYPE,V_RESOURCE_CATEGORY,V_RESOURCE_SUB_CAT, V_ANALYSIS_TYPE, 
                V_OPERATING_UNIT,   V_PRODUCT,      V_FUND,             V_CLASS_FLD,        V_PROGRAM_CODE, 
                V_BUDGET_REF,       V_AFFILIATE,    V_AFFILIATE_INTRA1, V_AFFILIATE_INTRA2, V_CHARTFIELD1,
                V_CHARTFIELD2,      V_CHARTFIELD3,  V_ALTACCT, V_DEPTID,V_FUND_LGY,         V_SUBFUND, 
                V_PROGRAM,          V_ELEMENT,      V_COMPONENT,        V_TASK,             V_PCA, 
                V_ORG_CODE,         V_INDEX_CODE,   V_OBJECT_DETAIL,    V_AGENCY_OBJECT,    V_SOURCE, 
                V_AGENCY_SOURCE_LGY,V_GL_ACCOUNT,   V_SUBSIDIARY,       V_FUND_SOURCE,      V_CHARACTER,
                V_METHOD,           V_YEAR,         V_REFERENCE,        V_FFY,              V_APPROPRIATION_SYMBOL, 
                V_PROJECT,          V_WORK_PHASE,   V_MULTIPURPOSE,     V_LOCATION,         V_DEPT_USE_1, 
                V_DEPT_USE_2,       V_BUDGET_DT,    V_LINE_DESCR,       V_OPEN_ITEM_KEY,    V_ACCTG_ENTRY_ID, 
                V_ROOT_DOCUMENT,    V_SUCCESS_FLAG, V_MESSAGE
                );
            
            --Update Header with Total mark record as NOT_TRANSMITTED if 0 and BATCH as N
            UPD_INFAR001_COUNTER_DATA(P_BATCH_ID, P_PROGRAM_UNIT, V_DATA_SOURCE_CODE, null, V_SUCCESS_FLAG, V_MESSAGE);
            
        END LOOP;
        CLOSE infar001Deposit_Cursor;
        
        DBMS_OUTPUT.PUT_LINE('Completed GET_INFAR001_DATA');  
        
    EXCEPTION
        WHEN OTHERS THEN
            --Handle Error
            DBMS_OUTPUT.PUT_LINE('GET_INFAR001_DATA: Failed to Get INFAR001 Data = ' || SQLERRM);
   	
            LOG_CARS_ERROR(
                p_errorLevel    => '3',
                p_severity      => c_HIGH_SEVERITY,
                p_errorDetail   => 'FISCAL GET_INFAR001_DATA procedure did not succeed',
                p_errorCode     => '5000',
                p_errorMessage  => 'GET_INFAR001_DATA: Failed to Get INFAR001 Data = ' || SQLERRM ,
                p_dataSource    => null
                );  
            
    END GET_INFAR001_DATA;
    
END FS_INTERFACE_PKG;
/
