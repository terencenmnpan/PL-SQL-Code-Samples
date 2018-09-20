CREATE OR REPLACE PACKAGE BODY FS_DATA_FILE_PKG AS
/******************************************************************************
   NAME:       FS_DATA_FILE_PKG
   PURPOSE:

   REVISIONS:
   Ver        Date        Author           Description
   ---------  ----------  ---------------  ------------------------------------
   1.0        02/07/2018  Vinaykumar Patil 1. Created for Financial Information System of California Interface
                                              Added Functions and Procedures
                                          1.EXTRACT_INFAR006_DATA Function
                                          2.EXTRACT_INFAR001_DATA Function
              02/22/2018  Vinaykumar Patil 1.Added Constants and modified the functions  
              02/25/2018  Vinaykumar Patil 1.Added procedure UPD_ACCTG_EVENT_STATUS  
              03/2/2018   Vinaykumar Patil 1.Added procedure LOG_CARS_ERROR and FS_DATA_FILE_PROCESSING  
              03/15/2018  Vinaykumar Patil 1.New column usage in INFAR001 table   
              03/29/2018  Vinaykumar Patil 1.New procedure for infar006 and in INFAR001 
              04/2/2018   Vinaykumar Patil 1.Added overloaded procedures EXTRACT_INFAR006_DATA, EXTRACT_INFAR001_DATA 
              04/3/2018   Vinaykumar Patil 1.Added procedures UPD_FISCAL_BATCH, UPD_INTERFACE_DATA 
              04/4/2018   Vinaykumar Patil 1.Added procedures GET_FISCAL_BATCH_ID and modified UPD_ACCTG_EVENT_STATUS
              04/05/2015  Vinaykumar Patil 1 Added procedure UPD_FISCAL_DATA_STATUS
              04/09/2018  Vinaykumar Patil 1 Modified the procedure to remove extra logic to check setup vs Adjustment
                                           2 Added parameter to INFAR006 Data File generation procedure
                                           3 Removed FS_DATA_FILE_PROCESSING procedure
              04/10/2018  Vinaykumar Patil 1 Modified the procedure to add more parameter to UPD_INTERFACE_DATA
              04/18/2018  Vinaykumar Patil 1 Removed Reference to INFAR006_PT and INFAR001_PT tables and added P_BATCH_FILE_NAME parameter
              05/1/2018   Vinaykumar Patil 1 Added Input parameter validation and CARS error logging in Data File Generation funcitons
              05/2/2018   Vinaykumar Patil 1 Added Batch Date Input parameter validation in Data File Generation funcitons
              06/6/2018   Vinaykumar Patil 1 For the Payment Reversal on Rolled Up Invoices CARS will not have older Payment Deposit Information
              09/13/2018  Vinaykumar Patil 1 Added procedures and logic for FISCAL INFAR018 related specification for row 001.
*****************************************************************************/
    PROCEDURE LOG_CARS_ERROR(
                p_errorLevel    CARS_ERROR_LOG.ERROR_LEVEL%TYPE,
                p_severity      CARS_ERROR_LOG.SEVERITY%TYPE,
                p_errorDetail   CARS_ERROR_LOG.ERROR_DETAIL%TYPE,
                p_errorCode     CARS_ERROR_LOG.ERROR_CODE%TYPE,
                p_errorMessage  CARS_ERROR_LOG.ERROR_MESSAGE%TYPE,
                p_dataSource    CARS_ERROR_LOG.DATA_SOURCE_CODE%TYPE
                )  IS  PRAGMA AUTONOMOUS_TRANSACTION;
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
             
         END IF;   

        COMMIT;
        
    EXCEPTION
        WHEN OTHERS THEN
            v_error_code := SQLCODE;
            v_error_msg := SUBSTR(SQLERRM, 1 , 100);
            DBMS_OUTPUT.PUT_LINE('The Error could not be logged '|| v_error_code || ': ' || v_error_msg);

    END LOG_CARS_ERROR;

    FUNCTION EXTRACT_INFAR006_DATA( P_SUBPROGRAM_GROUP  VARCHAR2, 
                                    P_TRANSACT_TYPE     VARCHAR2,
                                    P_BATCH_TYPE_CODE   BATCH.BATCH_TYPE_CODE%TYPE,
                                    P_BATCH_DATE        BATCH.CREATED_DATE%TYPE
                                   )  RETURN INFAR_DATA_TABLE PIPELINED IS

    v_RECORD            INFAR_REC_TYPE;
    
    v_BATCH_TYPE        VARCHAR2(5);
    v_BATCH_DATE        BATCH.BATCH_DATE%TYPE;
    v_ERROR_DETAIL      CARS_ERROR_LOG.ERROR_DETAIL%TYPE;
    v_ERROR_MESSAGE     CARS_ERROR_LOG.ERROR_MESSAGE%TYPE;
    v_VALID_DATA        VARCHAR2(1)             := c_YES;                   

    BEGIN

        v_ERROR_MESSAGE := 'P_SUBPROGRAM_GROUP= '||P_SUBPROGRAM_GROUP||' P_BATCH_TYPE_CODE = '||P_BATCH_TYPE_CODE||' P_TRANSACT_TYPE = '||P_TRANSACT_TYPE||' P_BATCH_DATE= '||P_BATCH_DATE||' v_VALID_DATA= '||v_VALID_DATA;
            
        -- Validate the Input parameters for  Data file generateion for Program Units Integrated to CARS (EV, PV, ART and CALOSHA)
        IF (P_SUBPROGRAM_GROUP IS NULL) OR (P_BATCH_TYPE_CODE IS NULL) OR (P_TRANSACT_TYPE IS NULL) OR (P_BATCH_DATE IS NULL) THEN 

            v_VALID_DATA    := C_NO;
            v_ERROR_DETAIL  := 'EXTRACT_INFAR006_DATA: One of the input parameters to Interface data file generation for the batch type '||P_BATCH_TYPE_CODE||' is missing';

        ELSE
        
            IF (P_SUBPROGRAM_GROUP NOT IN (c_PU_CARS)) THEN

                v_VALID_DATA    := C_NO;
                v_ERROR_DETAIL  := 'EXTRACT_INFAR006_DATA: The input parameters to Interface data file generation for subprogram '||P_SUBPROGRAM_GROUP||' is invalid';
            
            END IF;
            
            IF (P_BATCH_TYPE_CODE NOT IN (c_INFAR006_BATCH||'_'||c_PU_CARS||'_'||c_BATCH_TYPE_SETUP, c_INFAR006_BATCH||'_'||c_PU_CARS||'_'||c_BATCH_TYPE_ADJUST)) THEN

                v_VALID_DATA    := C_NO;
                v_ERROR_DETAIL  := 'EXTRACT_INFAR006_DATA: The input parameters to Interface data file generation for batch type code '||P_BATCH_TYPE_CODE||' is invalid';

            END IF;            

            IF (P_TRANSACT_TYPE NOT IN (c_BATCH_TYPE_SETUP,c_BATCH_TYPE_ADJUST)) THEN

                v_VALID_DATA    := C_NO;
                v_ERROR_DETAIL  := 'EXTRACT_INFAR006_DATA: The input parameters to Interface data file generation for transaction type code '||P_TRANSACT_TYPE||' is invalid';

            END IF;    

            SELECT TO_CHAR(P_BATCH_DATE, c_BATCH_DATE_FORMAT) INTO v_BATCH_DATE FROM DUAL;
            
            IF (TRUNC(P_BATCH_DATE) < c_SYSDATE)  THEN
            
                v_VALID_DATA    := C_NO;
                v_ERROR_DETAIL  := 'EXTRACT_INFAR006_DATA: The input parameters to Interface data file generation for batch date '||P_BATCH_DATE||' older date and is invalid';

            ELSIF (TRUNC(P_BATCH_DATE) > c_SYSDATE)  THEN

                v_VALID_DATA    := C_NO;
                v_ERROR_DETAIL  := 'EXTRACT_INFAR006_DATA: The input parameters to Interface data file generation for batch date '||P_BATCH_DATE||' future date and is invalid';

            END IF;  

        END IF;
    
        IF (v_VALID_DATA = C_NO) THEN
                            
            LOG_CARS_ERROR(
                p_errorLevel    => 2,
                p_severity      => c_MEDIUM_SEVERITY,
                p_errorDetail   => v_ERROR_DETAIL,
                p_errorCode     => 5002,
                p_errorMessage  => v_ERROR_MESSAGE,
                p_dataSource    => c_CARS_DB
                );
        END IF;
        
        IF (v_VALID_DATA = C_YES) THEN 
            -- 4/5/2018, Vinay Patil: Logic added to check if the Batch Type is Setup or Adjustment
            IF (REGEXP_LIKE (UPPER(trim(P_TRANSACT_TYPE)),c_BATCH_TYPE_SETUP)) THEN 
                v_BATCH_TYPE := c_BATCH_TYPE_SETUP;

            ELSIF (REGEXP_LIKE (UPPER(trim(P_TRANSACT_TYPE)),c_BATCH_TYPE_ADJUST)) THEN
                v_BATCH_TYPE := c_BATCH_TYPE_ADJUST;
             
            END IF;
        END IF;
        -- VINAY PATIL, 3/27/2018: ALL AR SETUP TRANSACTIONS
        IF (P_SUBPROGRAM_GROUP IN (c_PU_CARS)) AND (v_BATCH_TYPE = c_BATCH_TYPE_SETUP) AND (v_VALID_DATA = C_YES) THEN 
        
            FOR I IN (
                SELECT INFAR006_DATA.DATA_RECORD
                FROM
                    (
                    SELECT  
                        TRIM(IOD.GROUP_BU)                                              ||c_DELIMITER||
                        TRIM(IOD.GROUP_ID_STG)                                          ||c_DELIMITER||
                        TO_CHAR(IOD.ACCOUNTING_DT,  c_DATE_FORMAT)                      ||c_DELIMITER||
                        TRIM(IOD.GROUP_TYPE)                                            ||c_DELIMITER||
                        TO_CHAR(IOD.CONTROL_AMT,    c_AMOUNT_FORMAT)                    ||c_DELIMITER||
                        TRIM(IOD.CONTROL_CNT)                                           ||c_DELIMITER||
                        TRIM(IOD.POST_ACTION)                                           ||c_DELIMITER||
                        TRIM(IOD.GROUP_SEQ_NUM)                                         ||c_DELIMITER||
                        TRIM(IOD.CUST_ID)                                               ||c_DELIMITER||
                        TRIM(IOD.ITEM)                                                  ||c_DELIMITER||
                        TRIM(IOD.ITEM_LINE)                                             ||c_DELIMITER||
                        TRIM(IOD.ENTRY_TYPE)                                            ||c_DELIMITER||
                        TRIM(IOD.ENTRY_REASON)                                          ||c_DELIMITER||
                        TO_CHAR(IOD.ENTRY_AMT,      c_AMOUNT_FORMAT)                    ||c_DELIMITER||
                        TO_CHAR(IOD.ACCOUNTING_DT,  c_DATE_FORMAT)                      ||c_DELIMITER||
                        TO_CHAR(IOD.ASOF_DT,        c_DATE_FORMAT)                      ||c_DELIMITER||
                        TRIM(IOD.PYMNT_TERMS_CD)                                        ||c_DELIMITER||
                        TO_CHAR(IOD.DUE_DT,         c_DATE_FORMAT)                      ||c_DELIMITER||
                        TRIM(IOD.CR_ANALYST)                                            ||c_DELIMITER||
                        TRIM(IOD.COLLECTOR)                                             ||c_DELIMITER||
                        TRIM(IOD.PO_REF)                                                ||c_DELIMITER||
                        TRIM(IOD.DOCUMENT)                                              ||c_DELIMITER||
                        TRIM(IOD.CONTRACT_NUM)                                          ||c_DELIMITER||
                        TRIM(IOD.DISPUTE_CHKBOX)                                        ||c_DELIMITER||
                        TRIM(IOD.DISPUTE_STATUS)                                        ||c_DELIMITER||
                        TO_CHAR(IOD.DISPUTE_DATE,   c_DATE_FORMAT)                      ||c_DELIMITER||
                        TO_CHAR(IOD.DISPUTE_AMOUNT, c_AMOUNT_FORMAT)                    ||c_DELIMITER||
                        TRIM(IOD.COLLECTION_CHKBOX)                                     ||c_DELIMITER||
                        TRIM(IOD.COLLECTION_STATUS)                                     ||c_DELIMITER||
                        TO_CHAR(IOD.COLLECTION_DT,  c_DATE_FORMAT)                      ||c_DELIMITER||
                        TRIM(IOD.ADDRESS_SEQ_NUM)                                       ||c_DELIMITER||
                        TO_CHAR(IOD.USER_DT1,       c_DATE_FORMAT)                      ||c_DELIMITER||
                        TO_CHAR(IOD.USER_DT2,       c_DATE_FORMAT)                      ||c_DELIMITER||
                        TO_CHAR(IOD.USER_DT3,       c_DATE_FORMAT)                      ||c_DELIMITER||
                        TO_CHAR(IOD.USER_DT4,       c_DATE_FORMAT)                      ||c_DELIMITER||
                        TRIM(IOD.DST_SEQ_NUM)                                           ||c_DELIMITER||
                        TRIM(IOD.SYSTEM_DEFINED)                                        ||c_DELIMITER||
                        TO_CHAR(IOD.MONETARY_AMOUNT,c_AMOUNT_FORMAT)                    ||c_DELIMITER||
                        TRIM(IOD.BUSINESS_UNIT_GL)                                      ||c_DELIMITER||
                        TRIM(IOD.ACCOUNT)                                               ||c_DELIMITER||
                        TRIM(IOD.ALTACCT)                                               ||c_DELIMITER||
                        TRIM(IOD.DEPTID)                                                ||c_DELIMITER||
                        TRIM(IOD.OPERATING_UNIT)                                        ||c_DELIMITER||
                        TRIM(IOD.PRODUCT)                                               ||c_DELIMITER||
                        TRIM(IOD.FUND_CODE)                                             ||c_DELIMITER||
                        TRIM(IOD.CLASS_FLD)                                             ||c_DELIMITER||
                        TRIM(IOD.PROGRAM_CODE)                                          ||c_DELIMITER||
                        TRIM(IOD.BUDGET_REF)                                            ||c_DELIMITER||
                        TRIM(IOD.AFFILIATE)                                             ||c_DELIMITER||
                        TRIM(IOD.AFFILIATE_INTRA1)                                      ||c_DELIMITER||
                        TRIM(IOD.AFFILIATE_INTRA2)                                      ||c_DELIMITER||
                        TRIM(IOD.CHARTFIELD1)                                           ||c_DELIMITER||
                        TRIM(IOD.CHARTFIELD2)                                           ||c_DELIMITER||
                        TRIM(IOD.CHARTFIELD3)                                           ||c_DELIMITER||
                        TRIM(IOD.BUSINESS_UNIT_PC)                                      ||c_DELIMITER||
                        TRIM(IOD.PROJECT_ID)                                            ||c_DELIMITER||
                        TRIM(IOD.ACTIVITY_ID)                                           ||c_DELIMITER||
                        TRIM(IOD.RESOURCE_TYPE)                                         ||c_DELIMITER||
                        TRIM(IOD.RESOURCE_CATEGORY)                                     ||c_DELIMITER||
                        TRIM(IOD.RESOURCE_SUB_CAT)                                      ||c_DELIMITER||
                        TRIM(IOD.ANALYSIS_TYPE)                                         ||c_DELIMITER||
                        TRIM(IOD.ZZ_FUND)                                               ||c_DELIMITER||
                        TRIM(IOD.ZZ_SUB_FUND)                                           ||c_DELIMITER||
                        TRIM(IOD.ZZ_PROGRAM)                                            ||c_DELIMITER||
                        TRIM(IOD.ZZ_ELEMENT)                                            ||c_DELIMITER||
                        TRIM(IOD.ZZ_COMPONENT)                                          ||c_DELIMITER||
                        TRIM(IOD.ZZ_TASK)                                               ||c_DELIMITER||
                        TRIM(IOD.ZZ_PROG_COST_ACCT)                                     ||c_DELIMITER||
                        TRIM(IOD.ZZ_ORG_CODE)                                           ||c_DELIMITER||
                        TRIM(IOD.ZZ_INT_STRUCT1)                                        ||c_DELIMITER||
                        TRIM(IOD.ZZ_INT_STRUCT2)                                        ||c_DELIMITER||
                        TRIM(IOD.ZZ_INT_STRUCT3)                                        ||c_DELIMITER||
                        TRIM(IOD.ZZ_INT_STRUCT4)                                        ||c_DELIMITER||
                        TRIM(IOD.ZZ_INT_STRUCT5)                                        ||c_DELIMITER||
                        TRIM(IOD.ZZ_INDEX)                                              ||c_DELIMITER||
                        TRIM(IOD.ZZ_OBJ_DETAIL)                                         ||c_DELIMITER||
                        TRIM(IOD.ZZ_AGNCY_OBJ)                                          ||c_DELIMITER||
                        TRIM(IOD.ZZ_SOURCE)                                             ||c_DELIMITER||
                        TRIM(IOD.ZZ_AGNCY_SRC)                                          ||c_DELIMITER||
                        TRIM(IOD.ZZ_GL_ACCOUNT)                                         ||c_DELIMITER||
                        TRIM(IOD.ZZ_SUBSIDIARY)                                         ||c_DELIMITER||
                        TRIM(IOD.ZZ_FUND_SRC)                                           ||c_DELIMITER||
                        TRIM(IOD.ZZ_CHARACTER)                                          ||c_DELIMITER||
                        TRIM(IOD.ZZ_METHOD)                                             ||c_DELIMITER||
                        TRIM(IOD.ZZ_ENACTMENT_YEAR)                                     ||c_DELIMITER||
                        TRIM(IOD.ZZ_REFERENCE)                                          ||c_DELIMITER||
                        TRIM(IOD.ZZ_FISCAL_YEAR)                                        ||c_DELIMITER||
                        TRIM(IOD.ZZ_APPROP_SYMB)                                        ||c_DELIMITER||
                        TRIM(IOD.ZZ_PROJECT)                                            ||c_DELIMITER||
                        TRIM(IOD.ZZ_WORK_PHASE)                                         ||c_DELIMITER||
                        TRIM(IOD.ZZ_MULTIPURPOSE)                                       ||c_DELIMITER||
                        TRIM(IOD.ZZ_LOCATION)                                           ||c_DELIMITER||
                        TRIM(IOD.ZZ_DEPT_USE_1)                                         ||c_DELIMITER||
                        TRIM(IOD.ZZ_DEPT_USE_2)                                         ||c_DELIMITER||
                        TRIM(IOD.BUDGET_DT)                                             ||c_DELIMITER||
                      CHR(13)   DATA_RECORD,
                      IOD.INFAR006_OUTBOUND_ID,
                      1         SORT_ORDER
                    FROM
                        INFAR006_OUTBOUND IOD ,BATCH B
                    WHERE IOD.BATCH_ID          = B.BATCH_ID
                    AND   B.BATCH_TYPE_CODE     = P_BATCH_TYPE_CODE
                    AND   B.BATCH_DATE          = V_BATCH_DATE
                    AND   B.STATUS              = c_BATCH_COMPLETED
                    AND   IOD.STATUS            = c_NEW_STATUS
                    AND   IOD.DATA_SOURCE_CODE  = c_PU_CARS
                    ORDER BY IOD.INFAR006_OUTBOUND_ID ASC
                ) INFAR006_DATA

              ) LOOP 
                
                    v_RECORD.INFAR_DATA_RECORD  := i.DATA_RECORD ;
                    
                    PIPE ROW(v_RECORD); 
              
              END LOOP;
        END IF;
    
        -- VINAY PATIL, 3/27/2018: ALL ADJUSTMENT TRANSACTIONS
        IF (P_SUBPROGRAM_GROUP IN (c_PU_CARS)) AND (v_BATCH_TYPE = c_BATCH_TYPE_ADJUST) AND (v_VALID_DATA = C_YES) THEN 
        
            FOR I IN (
                SELECT INFAR006_DATA.DATA_RECORD
                FROM
                    (
                    SELECT  
                        TRIM(IOD.GROUP_BU)                                              ||c_DELIMITER||
                        TRIM(IOD.GROUP_ID_STG)                                          ||c_DELIMITER||
                        TO_CHAR(IOD.ACCOUNTING_DT,  c_DATE_FORMAT)                      ||c_DELIMITER||
                        TRIM(IOD.GROUP_TYPE)                                            ||c_DELIMITER||
                        TO_CHAR(IOD.CONTROL_AMT,    c_AMOUNT_FORMAT)                    ||c_DELIMITER||
                        TRIM(IOD.CONTROL_CNT)                                           ||c_DELIMITER||
                        TRIM(IOD.POST_ACTION)                                           ||c_DELIMITER||
                        TRIM(IOD.GROUP_SEQ_NUM)                                         ||c_DELIMITER||
                        TRIM(IOD.CUST_ID)                                               ||c_DELIMITER||
                        TRIM(IOD.ITEM)                                                  ||c_DELIMITER||
                        TRIM(IOD.ITEM_LINE)                                             ||c_DELIMITER||
                        TRIM(IOD.ENTRY_TYPE)                                            ||c_DELIMITER||
                        TRIM(IOD.ENTRY_REASON)                                          ||c_DELIMITER||
                        TO_CHAR(IOD.ENTRY_AMT,      c_AMOUNT_FORMAT)                    ||c_DELIMITER||
                        TO_CHAR(IOD.ACCOUNTING_DT,  c_DATE_FORMAT)                      ||c_DELIMITER||
                        TO_CHAR(IOD.ASOF_DT,        c_DATE_FORMAT)                      ||c_DELIMITER||
                        TRIM(IOD.PYMNT_TERMS_CD)                                        ||c_DELIMITER||
                        TO_CHAR(IOD.DUE_DT,         c_DATE_FORMAT)                      ||c_DELIMITER||
                        TRIM(IOD.CR_ANALYST)                                            ||c_DELIMITER||
                        TRIM(IOD.COLLECTOR)                                             ||c_DELIMITER||
                        TRIM(IOD.PO_REF)                                                ||c_DELIMITER||
                        TRIM(IOD.DOCUMENT)                                              ||c_DELIMITER||
                        TRIM(IOD.CONTRACT_NUM)                                          ||c_DELIMITER||
                        TRIM(IOD.DISPUTE_CHKBOX)                                        ||c_DELIMITER||
                        TRIM(IOD.DISPUTE_STATUS)                                        ||c_DELIMITER||
                        TO_CHAR(IOD.DISPUTE_DATE,   c_DATE_FORMAT)                      ||c_DELIMITER||
                        TO_CHAR(IOD.DISPUTE_AMOUNT, c_AMOUNT_FORMAT)                    ||c_DELIMITER||
                        TRIM(IOD.COLLECTION_CHKBOX)                                     ||c_DELIMITER||
                        TRIM(IOD.COLLECTION_STATUS)                                     ||c_DELIMITER||
                        TO_CHAR(IOD.COLLECTION_DT,  c_DATE_FORMAT)                      ||c_DELIMITER||
                        TRIM(IOD.ADDRESS_SEQ_NUM)                                       ||c_DELIMITER||
                        TO_CHAR(IOD.USER_DT1,       c_DATE_FORMAT)                      ||c_DELIMITER||
                        TO_CHAR(IOD.USER_DT2,       c_DATE_FORMAT)                      ||c_DELIMITER||
                        TO_CHAR(IOD.USER_DT3,       c_DATE_FORMAT)                      ||c_DELIMITER||
                        TO_CHAR(IOD.USER_DT4,       c_DATE_FORMAT)                      ||c_DELIMITER||
                        TRIM(IOD.DST_SEQ_NUM)                                           ||c_DELIMITER||
                        TRIM(IOD.SYSTEM_DEFINED)                                        ||c_DELIMITER||
                        TO_CHAR(IOD.MONETARY_AMOUNT,c_AMOUNT_FORMAT)                    ||c_DELIMITER||
                        TRIM(IOD.BUSINESS_UNIT_GL)                                      ||c_DELIMITER||
                        TRIM(IOD.ACCOUNT)                                               ||c_DELIMITER||
                        TRIM(IOD.ALTACCT)                                               ||c_DELIMITER||
                        TRIM(IOD.DEPTID)                                                ||c_DELIMITER||
                        TRIM(IOD.OPERATING_UNIT)                                        ||c_DELIMITER||
                        TRIM(IOD.PRODUCT)                                               ||c_DELIMITER||
                        TRIM(IOD.FUND_CODE)                                             ||c_DELIMITER||
                        TRIM(IOD.CLASS_FLD)                                             ||c_DELIMITER||
                        TRIM(IOD.PROGRAM_CODE)                                          ||c_DELIMITER||
                        TRIM(IOD.BUDGET_REF)                                            ||c_DELIMITER||
                        TRIM(IOD.AFFILIATE)                                             ||c_DELIMITER||
                        TRIM(IOD.AFFILIATE_INTRA1)                                      ||c_DELIMITER||
                        TRIM(IOD.AFFILIATE_INTRA2)                                      ||c_DELIMITER||
                        TRIM(IOD.CHARTFIELD1)                                           ||c_DELIMITER||
                        TRIM(IOD.CHARTFIELD2)                                           ||c_DELIMITER||
                        TRIM(IOD.CHARTFIELD3)                                           ||c_DELIMITER||
                        TRIM(IOD.BUSINESS_UNIT_PC)                                      ||c_DELIMITER||
                        TRIM(IOD.PROJECT_ID)                                            ||c_DELIMITER||
                        TRIM(IOD.ACTIVITY_ID)                                           ||c_DELIMITER||
                        TRIM(IOD.RESOURCE_TYPE)                                         ||c_DELIMITER||
                        TRIM(IOD.RESOURCE_CATEGORY)                                     ||c_DELIMITER||
                        TRIM(IOD.RESOURCE_SUB_CAT)                                      ||c_DELIMITER||
                        TRIM(IOD.ANALYSIS_TYPE)                                         ||c_DELIMITER||
                        TRIM(IOD.ZZ_FUND)                                               ||c_DELIMITER||
                        TRIM(IOD.ZZ_SUB_FUND)                                           ||c_DELIMITER||
                        TRIM(IOD.ZZ_PROGRAM)                                            ||c_DELIMITER||
                        TRIM(IOD.ZZ_ELEMENT)                                            ||c_DELIMITER||
                        TRIM(IOD.ZZ_COMPONENT)                                          ||c_DELIMITER||
                        TRIM(IOD.ZZ_TASK)                                               ||c_DELIMITER||
                        TRIM(IOD.ZZ_PROG_COST_ACCT)                                     ||c_DELIMITER||
                        TRIM(IOD.ZZ_ORG_CODE)                                           ||c_DELIMITER||
                        TRIM(IOD.ZZ_INT_STRUCT1)                                        ||c_DELIMITER||
                        TRIM(IOD.ZZ_INT_STRUCT2)                                        ||c_DELIMITER||
                        TRIM(IOD.ZZ_INT_STRUCT3)                                        ||c_DELIMITER||
                        TRIM(IOD.ZZ_INT_STRUCT4)                                        ||c_DELIMITER||
                        TRIM(IOD.ZZ_INT_STRUCT5)                                        ||c_DELIMITER||
                        TRIM(IOD.ZZ_INDEX)                                              ||c_DELIMITER||
                        TRIM(IOD.ZZ_OBJ_DETAIL)                                         ||c_DELIMITER||
                        TRIM(IOD.ZZ_AGNCY_OBJ)                                          ||c_DELIMITER||
                        TRIM(IOD.ZZ_SOURCE)                                             ||c_DELIMITER||
                        TRIM(IOD.ZZ_AGNCY_SRC)                                          ||c_DELIMITER||
                        TRIM(IOD.ZZ_GL_ACCOUNT)                                         ||c_DELIMITER||
                        TRIM(IOD.ZZ_SUBSIDIARY)                                         ||c_DELIMITER||
                        TRIM(IOD.ZZ_FUND_SRC)                                           ||c_DELIMITER||
                        TRIM(IOD.ZZ_CHARACTER)                                          ||c_DELIMITER||
                        TRIM(IOD.ZZ_METHOD)                                             ||c_DELIMITER||
                        TRIM(IOD.ZZ_ENACTMENT_YEAR)                                     ||c_DELIMITER||
                        TRIM(IOD.ZZ_REFERENCE)                                          ||c_DELIMITER||
                        TRIM(IOD.ZZ_FISCAL_YEAR)                                        ||c_DELIMITER||
                        TRIM(IOD.ZZ_APPROP_SYMB)                                        ||c_DELIMITER||
                        TRIM(IOD.ZZ_PROJECT)                                            ||c_DELIMITER||
                        TRIM(IOD.ZZ_WORK_PHASE)                                         ||c_DELIMITER||
                        TRIM(IOD.ZZ_MULTIPURPOSE)                                       ||c_DELIMITER||
                        TRIM(IOD.ZZ_LOCATION)                                           ||c_DELIMITER||
                        TRIM(IOD.ZZ_DEPT_USE_1)                                         ||c_DELIMITER||
                        TRIM(IOD.ZZ_DEPT_USE_2)                                         ||c_DELIMITER||
                        TRIM(IOD.BUDGET_DT)                                             ||c_DELIMITER||
                      CHR(13)   DATA_RECORD,
                      IOD.INFAR006_OUTBOUND_ID,
                      1         SORT_ORDER
                    FROM
                        INFAR006_OUTBOUND IOD ,BATCH B
                    WHERE IOD.BATCH_ID          = B.BATCH_ID
                    AND   B.BATCH_TYPE_CODE     = P_BATCH_TYPE_CODE
                    AND   B.BATCH_DATE          = V_BATCH_DATE
                    AND   B.STATUS              = c_BATCH_COMPLETED
                    AND   IOD.STATUS            = c_NEW_STATUS
                    AND   IOD.DATA_SOURCE_CODE  = c_PU_CARS
                    ORDER BY IOD.INFAR006_OUTBOUND_ID ASC
                ) INFAR006_DATA

              ) LOOP 
                
                    v_RECORD.INFAR_DATA_RECORD  := i.DATA_RECORD ;
                    
                    PIPE ROW(v_RECORD); 
              
              END LOOP;
        END IF;

      RETURN; 

    EXCEPTION
        WHEN OTHERS THEN
                LOG_CARS_ERROR(
                    p_errorLevel    => 1,
                    p_severity      => c_HIGH_SEVERITY,
                    p_errorDetail   => 'FISCAL INFAR006 Interface data file generation for the batch type '||P_BATCH_TYPE_CODE||' for the batch run on '||sysdate||' failed',
                    p_errorCode     => 5001,
                    p_errorMessage  => SQLERRM,
                    p_dataSource    => c_CARS_DB
                    );
                    
            RETURN;

    END EXTRACT_INFAR006_DATA;

    FUNCTION EXTRACT_INFAR001_DATA( P_SUBPROGRAM_GROUP  VARCHAR2, 
                                    P_BATCH_TYPE_CODE   BATCH.BATCH_TYPE_CODE%TYPE, 
                                    P_BATCH_DATE        BATCH.CREATED_DATE%TYPE)  
                                    RETURN INFAR_DATA_TABLE PIPELINED IS

    v_RECORD            INFAR_REC_TYPE;

    v_BATCH_DATE        BATCH.BATCH_DATE%TYPE;
    v_ERROR_DETAIL      CARS_ERROR_LOG.ERROR_DETAIL%TYPE;
    v_ERROR_MESSAGE     CARS_ERROR_LOG.ERROR_MESSAGE%TYPE;
    v_VALID_DATA        VARCHAR2(1)             := c_YES;                   

    BEGIN

        v_ERROR_MESSAGE := 'P_SUBPROGRAM_GROUP= '||P_SUBPROGRAM_GROUP||' P_BATCH_TYPE_CODE = '||P_BATCH_TYPE_CODE||' P_BATCH_DATE= '||P_BATCH_DATE||' v_VALID_DATA= '||v_VALID_DATA;
            
        -- Validate the Input parameters for  Data file generateion for Program Units Integrated to CARS (EV, PV, ART and CALOSHA)
        IF (P_SUBPROGRAM_GROUP IS NULL) OR (P_BATCH_TYPE_CODE IS NULL) OR (P_BATCH_DATE IS NULL) THEN 

            v_VALID_DATA    := C_NO;
            v_ERROR_DETAIL  := 'EXTRACT_INFAR001_DATA: One of the input parameters to Interface data file generation for the batch type '||P_BATCH_TYPE_CODE||' is missing';

        ELSE
        
            IF (P_SUBPROGRAM_GROUP NOT IN (c_PU_CARS)) THEN

                v_VALID_DATA    := C_NO;
                v_ERROR_DETAIL  := 'EXTRACT_INFAR001_DATA: The input parameters to Interface data file generation for subprogram '||P_SUBPROGRAM_GROUP||' is invalid';
            
            END IF;
            
            IF (P_BATCH_TYPE_CODE NOT IN (c_INFAR001_BATCH||'_'||c_PU_CARS)) THEN

                v_VALID_DATA    := C_NO;
                v_ERROR_DETAIL  := 'EXTRACT_INFAR001_DATA: The input parameters to Interface data file generation for batch type code '||P_BATCH_TYPE_CODE||' is invalid';

            END IF;             

            SELECT TO_CHAR(P_BATCH_DATE, c_BATCH_DATE_FORMAT) INTO v_BATCH_DATE FROM DUAL;
            
            IF (TRUNC(P_BATCH_DATE) < c_SYSDATE)  THEN
            
                v_VALID_DATA    := C_NO;
                v_ERROR_DETAIL  := 'EXTRACT_INFAR001_DATA: The input parameters to Interface data file generation for batch date '||P_BATCH_DATE||' older date and is invalid';

            ELSIF (TRUNC(P_BATCH_DATE) > c_SYSDATE)  THEN

                v_VALID_DATA    := C_NO;
                v_ERROR_DETAIL  := 'EXTRACT_INFAR001_DATA: The input parameters to Interface data file generation for batch date '||P_BATCH_DATE||' future date and is invalid';

            END IF;  

        END IF;
    
        IF (v_VALID_DATA = C_NO) THEN
                            
            LOG_CARS_ERROR(
                p_errorLevel    => 2,
                p_severity      => c_MEDIUM_SEVERITY,
                p_errorDetail   => v_ERROR_DETAIL,
                p_errorCode     => 5002,
                p_errorMessage  => v_ERROR_MESSAGE,
                p_dataSource    => c_CARS_DB
                );
        END IF;
        
        -- Prepare Data file for Program Units Integrated to CARS (EV, PV, ART and CALOSHA)
        IF (P_SUBPROGRAM_GROUP IN (c_PU_CARS)) AND (v_VALID_DATA = C_YES) THEN 

            -- 4/24/2018: Vinay Patil : Separated the Header from rest of the transactions.
            FOR c_HEADER_REC IN (
                SELECT INFAR001_DATA.DATA_RECORD
                FROM
                    (
                    SELECT  
                      IOD.FS_ROW_ID                                                             ||
                      RPAD(TO_CHAR(IOD.CREATED_DTTM,c_DTTM_FORMAT),26)                          ||
                      RPAD(TRIM(IOD.DEPOSIT_BU),5)                                              ||
                      RPAD(TO_CHAR(NVL(IOD.DEPOSIT_CNT,0)),4,' ')                               ||
                      RPAD(TO_CHAR(NVL(IOD.TOTAL_AMT,0),c_AMOUNT_FORMAT),28)                    ||
                      CHR(13)   DATA_RECORD,
                      IOD.INFAR001_OUTBOUND_ID,
                      IOD.FS_ROW_ID ROW_ID,
                      IOD.DEPOSIT_ID,
                      IOD.PAYMENT_SEQ_NUM,
                      1         SORT_ORDER
                    FROM
                        INFAR001_OUTBOUND IOD,BATCH B
                    WHERE IOD.BATCH_ID      = B.BATCH_ID
                    AND   B.BATCH_TYPE_CODE = P_BATCH_TYPE_CODE
                    AND   B.BATCH_DATE      = V_BATCH_DATE
                    AND   B.STATUS          = c_BATCH_COMPLETED
                    AND   IOD.STATUS        = c_NEW_STATUS
                    AND   IOD.FS_ROW_ID     = c_FH_ROW_ID
                ) INFAR001_DATA
                ORDER BY
                    INFAR001_DATA.INFAR001_OUTBOUND_ID, 
                    INFAR001_DATA.DEPOSIT_ID,
                    INFAR001_DATA.PAYMENT_SEQ_NUM,
                    INFAR001_DATA.ROW_ID,
                    INFAR001_DATA.SORT_ORDER       
              ) LOOP 
                
                    v_RECORD.INFAR_DATA_RECORD  := c_HEADER_REC.DATA_RECORD ;
                    
                    PIPE ROW(v_RECORD); 
              
              END LOOP;

            -- 6/6/2018, Vinay Patil : For the Payment Reversal on Rolled Up Invoices CARS will not have older Payment Deposit Information
            --                      : therefore these transaction caused formatting issue on the data file.Accounting Unit agreed to send
            --                      : blank values for Deposit Type and Deposit Slip. These Deposit id will fail in FISCAL, Accounting will
            --                      : update these in FISCAL applicatoin
             FOR I IN (
                SELECT INFAR001_DATA.DATA_RECORD
                FROM
                    (
                    SELECT  
                      IOD.FS_ROW_ID                                                                         ||
                      RPAD(TRIM(IOD.DEPOSIT_BU),5)                                                          ||
                      RPAD(TRIM(IOD.DEPOSIT_ID),15)                                                         ||
                      RPAD(TO_CHAR(IOD.ACCOUNTING_DT,c_DATE_FORMAT),10)                                     ||
                      RPAD(TRIM(IOD.BANK_CD),5)                                                             ||
                      RPAD(TRIM(IOD.BANK_ACCT_KEY),4)                                                       ||
                      RPAD(DECODE(IOD.DEPOSIT_TYPE,NULL,' ', TRIM(IOD.DEPOSIT_TYPE)),1,' ')                 ||
                      RPAD(TRIM(IOD.CONTROL_CURRENCY),3)                                                    ||
                      RPAD(DECODE(IOD.ZZ_BNK_DEPOSIT_NUM,NULL,' ',TRIM(IOD.ZZ_BNK_DEPOSIT_NUM)),10,' ')     ||
                      RPAD(TRIM(IOD.ZZ_IDENTIFIER),10)                                                      ||
                      RPAD(TO_CHAR(NVL(IOD.CONTROL_AMT ,0),c_AMOUNT_FORMAT),28)                             ||
                      RPAD(TO_CHAR(NVL(IOD.CONTROL_CNT,0)),6,' ')                                           ||
                      RPAD(TO_CHAR(IOD.RECEIVED_DT,c_DATE_FORMAT),10)                                   	||
                      CHR(13)   DATA_RECORD,
                      IOD.INFAR001_OUTBOUND_ID,
                      IOD.FS_ROW_ID ROW_ID,
                      IOD.DEPOSIT_ID,
                      IOD.PAYMENT_SEQ_NUM,
                      10         SORT_ORDER
                    FROM
                        INFAR001_OUTBOUND IOD,BATCH B
                    WHERE IOD.BATCH_ID      = B.BATCH_ID
                    AND   B.BATCH_TYPE_CODE = P_BATCH_TYPE_CODE
                    AND   B.BATCH_DATE      = V_BATCH_DATE
                    AND   B.STATUS          = c_BATCH_COMPLETED
                    AND   IOD.STATUS        = c_NEW_STATUS
                    AND   IOD.FS_ROW_ID     = c_DC_ROW_ID
                    UNION
                    SELECT  
                      IOD.FS_ROW_ID                                                                             ||
                      RPAD(TRIM(IOD.DEPOSIT_BU),5,' ')                                                          ||
                      RPAD(TRIM(IOD.DEPOSIT_ID),15,' ')                                                         ||
                      RPAD(TRIM(IOD.PAYMENT_SEQ_NUM),6,' ')                                                     ||
                      RPAD(TRIM(IOD.PAYMENT_ID),15,' ')                                                         ||
                      RPAD(TO_CHAR(IOD.ACCOUNTING_DT,c_DATE_FORMAT),10,' ')                                     ||
                      RPAD(TO_CHAR(NVL(IOD.PAYMENT_AMT ,0),c_AMOUNT_FORMAT),28)                                 ||
                      RPAD(TRIM(IOD.PAYMENT_CURRENCY),3,' ')                                                    ||
                      RPAD(TRIM(IOD.PP_SW),1,' ')                                                               ||
                      RPAD(TRIM(IOD.MISC_PAYMENT),1,' ')                                                        ||
                      RPAD(nvl(TO_CHAR(IOD.CHECK_DT,c_DATE_FORMAT),' '),10,' ')                                 ||
                      RPAD(TRIM(IOD.ZZ_PAYMENT_METHOD),3,' ')                                                   ||
                      RPAD(nvl(TRIM(IOD.ZZ_RECEIVED_BY_SCO),' '),1,' ')                                         ||
                      RPAD(nvl(TRIM(IOD.ZZ_CASH_TYPE),' '),3)                                                   ||
                      RPAD(DECODE(IOD.DESCR50_MIXED,NULL,' ', TRIM(IOD.DESCR50_MIXED)),50,' ')                  ||
                      RPAD(DECODE(IOD.DOCUMENT,NULL,' ',      TRIM(IOD.DOCUMENT)),30,' ')                       ||   
                      RPAD(DECODE(IOD.CITY,NULL,' ',          TRIM(IOD.CITY)),30,' ')                           ||
                      RPAD(DECODE(IOD.COUNTY,NULL,' ',        TRIM(IOD.COUNTY)),30,' ')                         ||
                      RPAD(DECODE(IOD.TAX_AMT,NULL,' ',       TO_CHAR(NVL(IOD.TAX_AMT ,0),c_AMOUNT_FORMAT)),28) ||
                      RPAD(DECODE(IOD.LINE_NOTE_TEXT,NULL,' ',TRIM(IOD.LINE_NOTE_TEXT)),254,' ')                ||
                      CHR(13)   DATA_RECORD,                  
                      IOD.INFAR001_OUTBOUND_ID,
                      IOD.FS_ROW_ID ROW_ID,
                      IOD.DEPOSIT_ID,
                      IOD.PAYMENT_SEQ_NUM,
                      11         SORT_ORDER
                    FROM
                        INFAR001_OUTBOUND IOD,BATCH B
                    WHERE IOD.BATCH_ID      = B.BATCH_ID
                    AND   B.BATCH_TYPE_CODE = P_BATCH_TYPE_CODE
                    AND   B.BATCH_DATE      = V_BATCH_DATE
                    AND   B.STATUS          = c_BATCH_COMPLETED
                    AND   IOD.STATUS        = c_NEW_STATUS
                    AND   IOD.FS_ROW_ID     = c_PI_ROW_ID
                    UNION
                    SELECT  
                      IOD.FS_ROW_ID                                                ||
                      RPAD(TRIM(IOD.DEPOSIT_BU),5)                                 ||
                      RPAD(TRIM(IOD.DEPOSIT_ID),15)                                ||
                      RPAD(TRIM(IOD.PAYMENT_SEQ_NUM),6)                            ||
                      RPAD(TRIM(IOD.ID_SEQ_NUM),5)                                 ||
                      RPAD(TRIM(IOD.REF_QUALIFIER_CODE),2)                         ||
                      RPAD(TRIM(IOD.REF_VALUE),30)                                 ||
                      CHR(13)   DATA_RECORD,
                      IOD.INFAR001_OUTBOUND_ID,
                      IOD.FS_ROW_ID ROW_ID,
                      IOD.DEPOSIT_ID,
                      IOD.PAYMENT_SEQ_NUM,
                      12         SORT_ORDER
                    FROM
                        INFAR001_OUTBOUND IOD,BATCH B
                    WHERE IOD.BATCH_ID      = B.BATCH_ID
                    AND   B.BATCH_TYPE_CODE = P_BATCH_TYPE_CODE
                    AND   B.BATCH_DATE      = V_BATCH_DATE
                    AND   B.STATUS          = c_BATCH_COMPLETED
                    AND   IOD.STATUS        = c_NEW_STATUS
                    AND   IOD.FS_ROW_ID     = c_IR_ROW_ID
                    UNION
                    SELECT  
                      IOD.FS_ROW_ID                                                ||
                      RPAD(TRIM(IOD.DEPOSIT_BU),5)                                 ||
                      RPAD(TRIM(IOD.DEPOSIT_ID),15)                                ||
                      RPAD(TRIM(IOD.PAYMENT_SEQ_NUM),6)                            ||
                      RPAD(TRIM(IOD.ID_SEQ_NUM),5)                                 ||
                      RPAD(TRIM(IOD.CUST_ID),15)                                   ||
                      CHR(13)   DATA_RECORD,
                      IOD.INFAR001_OUTBOUND_ID,
                      IOD.FS_ROW_ID ROW_ID,
                      IOD.DEPOSIT_ID,
                      IOD.PAYMENT_SEQ_NUM,
                      13         SORT_ORDER
                    FROM
                        INFAR001_OUTBOUND IOD,BATCH B
                    WHERE IOD.BATCH_ID      = B.BATCH_ID
                    AND   B.BATCH_TYPE_CODE = P_BATCH_TYPE_CODE
                    AND   B.BATCH_DATE      = V_BATCH_DATE
                    AND   B.STATUS          = c_BATCH_COMPLETED
                    AND   IOD.STATUS        = c_NEW_STATUS
                    AND   IOD.FS_ROW_ID     = c_CI_ROW_ID
                    UNION
                    SELECT  
                      IOD.FS_ROW_ID                                                                                  ||
                      RPAD(TRIM(IOD.DEPOSIT_BU),5,' ')                                                               ||
                      RPAD(TRIM(IOD.DEPOSIT_ID),15,' ')                                                              ||
                      RPAD(TRIM(IOD.PAYMENT_SEQ_NUM),6,' ')                                                          ||
                      RPAD(TRIM(IOD.DST_SEQ_NUM),6,' ')                                                              ||
                      RPAD(TRIM(IOD.BUSINESS_UNIT_GL),5,' ')                                                         ||
                      RPAD(DECODE(IOD.SPEEDCHART_KEY,NULL,' ',          TRIM(IOD.SPEEDCHART_KEY)),10,' ')            ||
                      RPAD(TO_CHAR(NVL(IOD.MONETARY_AMOUNT ,0),c_AMOUNT_FORMAT),28,CHR(32))                          ||
                      RPAD(DECODE(IOD.ACCOUNT,NULL,' ',                 TRIM(IOD.ACCOUNT)),10,' ')                   ||
                      RPAD(DECODE(IOD.BUSINESS_UNIT_PC,NULL,' ',        TRIM(IOD.BUSINESS_UNIT_PC)),5,' ')           ||
                      RPAD(DECODE(IOD.PROJECT_ID,NULL,' ',              TRIM(IOD.PROJECT_ID)),15,' ')                ||
                      RPAD(DECODE(IOD.ACTIVITY_ID,NULL,' ',             TRIM(IOD.ACTIVITY_ID)),15,' ')               ||
                      RPAD(DECODE(IOD.RESOURCE_TYPE,NULL,' ',           TRIM(IOD.RESOURCE_TYPE)),5,' ')              ||
                      RPAD(DECODE(IOD.RESOURCE_CATEGORY,NULL,' ',       TRIM(IOD.RESOURCE_CATEGORY)),5,' ')          ||
                      RPAD(DECODE(IOD.RESOURCE_SUB_CAT,NULL,' ',        TRIM(IOD.RESOURCE_SUB_CAT)),5,' ')           ||
                      RPAD(DECODE(IOD.ANALYSIS_TYPE,NULL,' ',           TRIM(IOD.ANALYSIS_TYPE)),3,' ')              ||
                      RPAD(DECODE(IOD.OPERATING_UNIT,NULL,' ',          TRIM(IOD.OPERATING_UNIT)),8,' ')             ||      
                      RPAD(DECODE(IOD.PRODUCT,NULL,' ',                 TRIM(IOD.PRODUCT)),6,' ')                    ||
                      RPAD(DECODE(IOD.FUND_CODE,NULL,' ',               TRIM(IOD.FUND_CODE)),9,' ')                  ||
                      RPAD(DECODE(IOD.CLASS_FLD,NULL,' ',               TRIM(IOD.CLASS_FLD)),5,' ')                  ||      
                      RPAD(DECODE(IOD.PROGRAM_CODE,NULL,' ',            TRIM(IOD.PROGRAM_CODE)),10,' ')              ||
                      RPAD(DECODE(IOD.BUDGET_REF,NULL,' ',              TRIM(IOD.BUDGET_REF)),8,' ')                 ||
                      RPAD(DECODE(IOD.AFFILIATE,NULL,' ',               TRIM(IOD.AFFILIATE)),5,' ')                  ||      
                      RPAD(DECODE(IOD.AFFILIATE_INTRA1,NULL,' ',        TRIM(IOD.AFFILIATE_INTRA1)),10,' ')          ||
                      RPAD(DECODE(IOD.AFFILIATE_INTRA2,NULL,' ',        TRIM(IOD.AFFILIATE_INTRA2)),10,' ')          ||      
                      RPAD(DECODE(IOD.CHARTFIELD1,NULL,' ',             TRIM(IOD.CHARTFIELD1)),10,' ')               ||
                      RPAD(DECODE(IOD.CHARTFIELD2,NULL,' ',             TRIM(IOD.CHARTFIELD2)),10,' ')               ||
                      RPAD(DECODE(IOD.CHARTFIELD3,NULL,' ',             TRIM(IOD.CHARTFIELD3)),10,' ')               ||
                      RPAD(DECODE(IOD.ALTACCT,NULL,' ',                 TRIM(IOD.ALTACCT)),10,' ')                   ||
                      RPAD(DECODE(IOD.DEPTID,NULL,' ',                  TRIM(IOD.DEPTID)),10,' ')                    ||
                      RPAD(DECODE(IOD.FUND,NULL,' ',                    TRIM(IOD.FUND)),4,' ')                       ||      
                      RPAD(DECODE(IOD.SUBFUND,NULL,' ',                 TRIM(IOD.SUBFUND)),3,' ')                    ||      
                      RPAD(DECODE(IOD.PROGRAM,NULL,' ',                 TRIM(IOD.PROGRAM)),2,' ')                    ||
                      RPAD(DECODE(IOD.ELEMENT,NULL,' ',                 TRIM(IOD.ELEMENT)),2,' ')                    ||                        
                      RPAD(DECODE(IOD.COMPONENT,NULL,' ',               TRIM(IOD.COMPONENT)),3,' ')                  ||
                      RPAD(DECODE(IOD.TASK,NULL,' ',                    TRIM(IOD.TASK)),3,' ')                       ||
                      RPAD(DECODE(IOD.PCA,NULL,' ',                     TRIM(IOD.PCA)),5,' ')                        ||
                      RPAD(DECODE(IOD.ORG_CODE,NULL,' ',                TRIM(IOD.ORG_CODE)),4,' ')                   ||
                      RPAD(DECODE(IOD.INTERNAL_ORG_STRUCTURE_1,NULL,' ',TRIM(IOD.INTERNAL_ORG_STRUCTURE_1)),10,' ')  ||
                      RPAD(DECODE(IOD.INTERNAL_ORG_STRUCTURE_2,NULL,' ',TRIM(IOD.INTERNAL_ORG_STRUCTURE_2)),10,' ')  ||
                      RPAD(DECODE(IOD.INTERNAL_ORG_STRUCTURE_3,NULL,' ',TRIM(IOD.INTERNAL_ORG_STRUCTURE_3)),10,' ')  ||      
                      RPAD(DECODE(IOD.INTERNAL_ORG_STRUCTURE_4,NULL,' ',TRIM(IOD.INTERNAL_ORG_STRUCTURE_4)),10,' ')  ||
                      RPAD(DECODE(IOD.INTERNAL_ORG_STRUCTURE_5,NULL,' ',TRIM(IOD.INTERNAL_ORG_STRUCTURE_5)),10,' ')  ||
                      RPAD(DECODE(IOD.INDEX_CODE,NULL,' ',              TRIM(IOD.INDEX_CODE)),4,' ')                 ||
                      RPAD(DECODE(IOD.OBJECT_DETAIL,NULL,' ',           TRIM(IOD.OBJECT_DETAIL)),3,' ')              ||
                      RPAD(DECODE(IOD.AGENCY_OBJECT,NULL,' ',           TRIM(IOD.AGENCY_OBJECT)),10,' ')             ||
                      RPAD(DECODE(IOD.SOURCE,NULL,' ',                  TRIM(IOD.SOURCE)),6,' ')                     ||
                      RPAD(DECODE(IOD.AGENCY_SOURCE,NULL,' ',           TRIM(IOD.AGENCY_SOURCE)),10,' ')             ||
                      RPAD(DECODE(IOD.GL_ACCOUNT,NULL,' ',              TRIM(IOD.GL_ACCOUNT)),4,' ')                 ||
                      RPAD(DECODE(IOD.SUBSIDIARY,NULL,' ',              TRIM(IOD.SUBSIDIARY)),8,' ')                 ||
                      RPAD(DECODE(IOD.FUND_SOURCE,NULL,' ',             TRIM(IOD.FUND_SOURCE)),1,' ')                ||
                      RPAD(DECODE(IOD.CHARACTER,NULL,' ',               TRIM(IOD.CHARACTER)),1,' ')                  ||
                      RPAD(DECODE(IOD.METHOD,NULL,' ',                  TRIM(IOD.METHOD)),1,' ')                     ||
                      RPAD(DECODE(IOD.YEAR,NULL,' ',                    TRIM(IOD.YEAR)),4,' ')                       ||
                      RPAD(DECODE(IOD.REFERENCE,NULL,' ',               TRIM(IOD.REFERENCE)),3,' ')                  ||
                      RPAD(DECODE(IOD.FFY,NULL,' ',                     TRIM(IOD.FFY)),4,' ')                        ||
                      RPAD(DECODE(IOD.APPROPRIATION_SYMBOL,NULL,' ',    TRIM(IOD.APPROPRIATION_SYMBOL)),3,' ')       ||
                      RPAD(DECODE(IOD.PROJECT,NULL,' ',                 TRIM(IOD.PROJECT)),10,' ')                   ||
                      RPAD(DECODE(IOD.WORK_PHASE,NULL,' ',              TRIM(IOD.WORK_PHASE)),10,' ')                ||
                      RPAD(DECODE(IOD.MULTIPURPOSE,NULL,' ',            TRIM(IOD.MULTIPURPOSE)),12,' ')              ||
                      RPAD(DECODE(IOD.LOCATION,NULL,' ',                TRIM(IOD.LOCATION)),6,' ')                   ||
                      RPAD(DECODE(IOD.DEPT_USE_1,NULL,' ',              TRIM(IOD.DEPT_USE_1)),20,' ')                ||
                      RPAD(DECODE(IOD.DEPT_USE_2,NULL,' ',              TRIM(IOD.DEPT_USE_2)),20,' ')                ||
                      RPAD(DECODE(IOD.BUDGET_DT,NULL,' ',               TRIM(IOD.BUDGET_DT)),10,' ')                 ||
                      RPAD(DECODE(IOD.LINE_DESCR,NULL,' ',              TRIM(IOD.LINE_DESCR)),30,' ')                ||
                      RPAD(DECODE(IOD.OPEN_ITEM_KEY,NULL,' ',           TRIM(IOD.OPEN_ITEM_KEY)),30,' ')             ||
                      CHR(13)   DATA_RECORD,
                      IOD.INFAR001_OUTBOUND_ID,
                      IOD.FS_ROW_ID ROW_ID,
                      IOD.DEPOSIT_ID,
                      IOD.PAYMENT_SEQ_NUM,
                      14         SORT_ORDER
                    FROM
                        INFAR001_OUTBOUND IOD,BATCH B 
                    WHERE IOD.BATCH_ID      = B.BATCH_ID
                    AND   B.BATCH_TYPE_CODE = P_BATCH_TYPE_CODE
                    AND   B.BATCH_DATE      = V_BATCH_DATE
                    AND   B.STATUS          = c_BATCH_COMPLETED
                    AND   IOD.STATUS        = c_NEW_STATUS
                    AND   IOD.FS_ROW_ID     = c_DJ_ROW_ID
                ) INFAR001_DATA
                ORDER BY
                    INFAR001_DATA.INFAR001_OUTBOUND_ID, 
                    INFAR001_DATA.DEPOSIT_ID,
                    INFAR001_DATA.PAYMENT_SEQ_NUM,
                    INFAR001_DATA.ROW_ID,
                    INFAR001_DATA.SORT_ORDER       
              ) LOOP 
                
                    v_RECORD.INFAR_DATA_RECORD  := i.DATA_RECORD ;
                    
                    PIPE ROW(v_RECORD); 
              
              END LOOP;
        END IF;

      RETURN; 
      
    EXCEPTION
        WHEN OTHERS THEN
                LOG_CARS_ERROR(
                    p_errorLevel    => 1,
                    p_severity      => c_HIGH_SEVERITY,
                    p_errorDetail   => 'FISCAL INFAR001 Interface data file generation for the batch type '||P_BATCH_TYPE_CODE||' failed',
                    p_errorCode     => 5002,
                    p_errorMessage  => SQLERRM,
                    p_dataSource    => c_CARS_DB
                    );
            RETURN;

    END EXTRACT_INFAR001_DATA;
    
    
    FUNCTION EXTRACT_INFAR018_DATA( P_SUBPROGRAM_GROUP  VARCHAR2, 
                                    P_BATCH_TYPE_CODE   BATCH.BATCH_TYPE_CODE%TYPE, 
                                    P_BATCH_DATE        BATCH.CREATED_DATE%TYPE)  
                                    RETURN INFAR_DATA_TABLE PIPELINED IS

    v_RECORD            INFAR_REC_TYPE;

    v_BATCH_DATE        BATCH.BATCH_DATE%TYPE;
    v_ERROR_DETAIL      CARS_ERROR_LOG.ERROR_DETAIL%TYPE;
    v_ERROR_MESSAGE     CARS_ERROR_LOG.ERROR_MESSAGE%TYPE;
    v_VALID_DATA        VARCHAR2(1)             := c_YES;                   

    BEGIN

        v_ERROR_MESSAGE := 'P_SUBPROGRAM_GROUP= '||P_SUBPROGRAM_GROUP||' P_BATCH_TYPE_CODE = '||P_BATCH_TYPE_CODE||' P_BATCH_DATE= '||P_BATCH_DATE||' v_VALID_DATA= '||v_VALID_DATA;
            
        -- Validate the Input parameters for  Data file generateion for Program Units Integrated to CARS (EV, PV, ART and CALOSHA)
        IF (P_SUBPROGRAM_GROUP IS NULL) OR (P_BATCH_TYPE_CODE IS NULL) OR (P_BATCH_DATE IS NULL) THEN 

            v_VALID_DATA    := C_NO;
            v_ERROR_DETAIL  := 'EXTRACT_INFAR018_DATA: One of the input parameters to Interface data file generation for the batch type '||P_BATCH_TYPE_CODE||' is missing';

        ELSE
        
            IF (P_SUBPROGRAM_GROUP NOT IN (c_PU_CARS)) THEN

                v_VALID_DATA    := C_NO;
                v_ERROR_DETAIL  := 'EXTRACT_INFAR018_DATA: The input parameters to Interface data file generation for subprogram '||P_SUBPROGRAM_GROUP||' is invalid';
            
            END IF;
            
            IF (P_BATCH_TYPE_CODE NOT IN (c_INFAR018_BATCH||'_'||c_PU_CARS)) THEN

                v_VALID_DATA    := C_NO;
                v_ERROR_DETAIL  := 'EXTRACT_INFAR018_DATA: The input parameters to Interface data file generation for batch type code '||P_BATCH_TYPE_CODE||' is invalid';

            END IF;             

            SELECT TO_CHAR(P_BATCH_DATE, c_BATCH_DATE_FORMAT) INTO v_BATCH_DATE FROM DUAL;
            
            IF (TRUNC(P_BATCH_DATE) < c_SYSDATE)  THEN
            
                v_VALID_DATA    := C_NO;
                v_ERROR_DETAIL  := 'EXTRACT_INFAR018_DATA: The input parameters to Interface data file generation for batch date '||P_BATCH_DATE||' older date and is invalid';

            ELSIF (TRUNC(P_BATCH_DATE) > c_SYSDATE)  THEN

                v_VALID_DATA    := C_NO;
                v_ERROR_DETAIL  := 'EXTRACT_INFAR018_DATA: The input parameters to Interface data file generation for batch date '||P_BATCH_DATE||' future date and is invalid';

            END IF;  

        END IF;
    
        IF (v_VALID_DATA = C_NO) THEN
                            
            LOG_CARS_ERROR(
                p_errorLevel    => 2,
                p_severity      => c_MEDIUM_SEVERITY,
                p_errorDetail   => v_ERROR_DETAIL,
                p_errorCode     => 5002,
                p_errorMessage  => v_ERROR_MESSAGE,
                p_dataSource    => c_CARS_DB
                );
        END IF;
        
        -- Prepare Data file for Program Units Integrated to CARS (EV, PV, ART and CALOSHA)
        IF (P_SUBPROGRAM_GROUP IN (c_PU_CARS)) AND (v_VALID_DATA = C_YES) THEN 

            -- 4/24/2018: Vinay Patil : Separated the Header from rest of the transactions.
            FOR c_HEADER_REC IN (
                SELECT INFAR018_DATA.DATA_RECORD
                FROM
                    (
                    SELECT  
                      IOD.FS_ROW_ID                                                             ||
                      RPAD(TO_CHAR(IOD.CREATED_DTTM,c_DTTM_FORMAT),26)                          ||
                      RPAD(TRIM(IOD.DEPOSIT_BU),5)                                              ||
                      RPAD(TO_CHAR(NVL(IOD.DEPOSIT_CNT,0)),4,' ')                               ||
                      RPAD(TO_CHAR(NVL(IOD.TOTAL_AMT,0),c_AMOUNT_FORMAT),28)                    ||
                      CHR(13)   DATA_RECORD,
                      IOD.INFAR001_OUTBOUND_ID,
                      IOD.FS_ROW_ID ROW_ID,
                      IOD.DEPOSIT_ID,
                      IOD.PAYMENT_SEQ_NUM,
                      1         SORT_ORDER
                    FROM
                        INFAR001_OUTBOUND IOD,BATCH B
                    WHERE IOD.BATCH_ID      = B.BATCH_ID
                    AND   B.BATCH_TYPE_CODE = P_BATCH_TYPE_CODE
                    AND   B.BATCH_DATE      = V_BATCH_DATE
                    AND   B.STATUS          = c_BATCH_COMPLETED
                    AND   IOD.STATUS        = c_NEW_STATUS
                    AND   IOD.FS_ROW_ID     = c_FH_ROW_ID
                ) INFAR018_DATA
                ORDER BY
                    INFAR018_DATA.INFAR001_OUTBOUND_ID, 
                    INFAR018_DATA.DEPOSIT_ID,
                    INFAR018_DATA.PAYMENT_SEQ_NUM,
                    INFAR018_DATA.ROW_ID,
                    INFAR018_DATA.SORT_ORDER       
              ) LOOP 
                
                    v_RECORD.INFAR_DATA_RECORD  := c_HEADER_REC.DATA_RECORD ;
                    
                    PIPE ROW(v_RECORD); 
              
              END LOOP;

            -- 9/13/2018,Vinay Patil : Added for columns for FISCAL INFAR018 related specification for row 001.
            -- 6/6/2018, Vinay Patil : For the Payment Reversal on Rolled Up Invoices CARS will not have older Payment Deposit Information
            --                      : therefore these transaction caused formatting issue on the data file.Accounting Unit agreed to send
            --                      : blank values for Deposit Type and Deposit Slip. These Deposit id will fail in FISCAL, Accounting will
            --                      : update these in FISCAL applicatoin
             FOR I IN (
                SELECT INFAR018_DATA.DATA_RECORD
                FROM
                    (
                    SELECT  
                      IOD.FS_ROW_ID                                                                         ||
                      RPAD(TRIM(IOD.DEPOSIT_BU),5)                                                          ||
                      RPAD(TRIM(IOD.DEPOSIT_ID),15)                                                         ||
                      RPAD(TO_CHAR(IOD.ACCOUNTING_DT,c_DATE_FORMAT),10)                                     ||
                      RPAD(TRIM(IOD.BANK_CD),5)                                                             ||
                      RPAD(TRIM(IOD.BANK_ACCT_KEY),4)                                                       ||
                      RPAD(DECODE(IOD.DEPOSIT_TYPE,NULL,' ', TRIM(IOD.DEPOSIT_TYPE)),1,' ')                 ||
                      RPAD(TRIM(IOD.CONTROL_CURRENCY),3)                                                    ||
                      RPAD(DECODE(IOD.ZZ_BNK_DEPOSIT_NUM,NULL,' ',TRIM(IOD.ZZ_BNK_DEPOSIT_NUM)),10,' ')     ||
                      RPAD(TRIM(IOD.ZZ_IDENTIFIER),10)                                                      ||
                      RPAD(TO_CHAR(NVL(IOD.CONTROL_AMT ,0),c_AMOUNT_FORMAT),28)                             ||
                      RPAD(TO_CHAR(NVL(IOD.CONTROL_CNT,0)),6,' ')                                           ||
                      RPAD(TO_CHAR(IOD.RECEIVED_DT,c_DATE_FORMAT),10)                                       ||
                      RPAD(DECODE(IOD.TOTAL_CHECKS,NULL,' ',    TRIM(IOD.TOTAL_CHECKS)),5,' ')              ||
                      RPAD(DECODE(IOD.FLAG,NULL,' ',            TRIM(IOD.FLAG)),1,' ')                      ||
                      RPAD(DECODE(IOD.BANK_OPER_NUM,NULL,' ',   TRIM(IOD.BANK_OPER_NUM)),2,' ')             ||
                      RPAD(DECODE(IOD.ZZ_LEG_DEP_ID,NULL,' ',   TRIM(IOD.ZZ_LEG_DEP_ID)),15,' ')            ||
                      CHR(13)   DATA_RECORD,
                      IOD.INFAR001_OUTBOUND_ID,
                      IOD.FS_ROW_ID ROW_ID,
                      IOD.DEPOSIT_ID,
                      IOD.PAYMENT_SEQ_NUM,
                      10         SORT_ORDER
                    FROM
                        INFAR001_OUTBOUND IOD,BATCH B
                    WHERE IOD.BATCH_ID      = B.BATCH_ID
                    AND   B.BATCH_TYPE_CODE = P_BATCH_TYPE_CODE
                    AND   B.BATCH_DATE      = V_BATCH_DATE
                    AND   B.STATUS          = c_BATCH_COMPLETED
                    AND   IOD.STATUS        = c_NEW_STATUS
                    AND   IOD.FS_ROW_ID     = c_DC_ROW_ID
                    UNION
                    SELECT  
                      IOD.FS_ROW_ID                                                                             ||
                      RPAD(TRIM(IOD.DEPOSIT_BU),5,' ')                                                          ||
                      RPAD(TRIM(IOD.DEPOSIT_ID),15,' ')                                                         ||
                      RPAD(TRIM(IOD.PAYMENT_SEQ_NUM),6,' ')                                                     ||
                      RPAD(TRIM(IOD.PAYMENT_ID),15,' ')                                                         ||
                      RPAD(TO_CHAR(IOD.ACCOUNTING_DT,c_DATE_FORMAT),10,' ')                                     ||
                      RPAD(TO_CHAR(NVL(IOD.PAYMENT_AMT ,0),c_AMOUNT_FORMAT),28)                                 ||
                      RPAD(TRIM(IOD.PAYMENT_CURRENCY),3,' ')                                                    ||
                      RPAD(TRIM(IOD.PP_SW),1,' ')                                                               ||
                      RPAD(TRIM(IOD.MISC_PAYMENT),1,' ')                                                        ||
                      RPAD(nvl(TO_CHAR(IOD.CHECK_DT,c_DATE_FORMAT),' '),10,' ')                                 ||
                      RPAD(TRIM(IOD.ZZ_PAYMENT_METHOD),3,' ')                                                   ||
                      RPAD(nvl(TRIM(IOD.ZZ_RECEIVED_BY_SCO),' '),1,' ')                                         ||
                      RPAD(nvl(TRIM(IOD.ZZ_CASH_TYPE),' '),3)                                                   ||
                      RPAD(DECODE(IOD.DESCR50_MIXED,NULL,' ', TRIM(IOD.DESCR50_MIXED)),50,' ')                  ||
                      RPAD(DECODE(IOD.DOCUMENT,NULL,' ',      TRIM(IOD.DOCUMENT)),30,' ')                       ||   
                      RPAD(DECODE(IOD.CITY,NULL,' ',          TRIM(IOD.CITY)),30,' ')                           ||
                      RPAD(DECODE(IOD.COUNTY,NULL,' ',        TRIM(IOD.COUNTY)),30,' ')                         ||
                      RPAD(DECODE(IOD.TAX_AMT,NULL,' ',       TO_CHAR(NVL(IOD.TAX_AMT ,0),c_AMOUNT_FORMAT)),28) ||
                      RPAD(DECODE(IOD.LINE_NOTE_TEXT,NULL,' ',TRIM(IOD.LINE_NOTE_TEXT)),255,' ')                ||
                      CHR(13)   DATA_RECORD,                  
                      IOD.INFAR001_OUTBOUND_ID,
                      IOD.FS_ROW_ID ROW_ID,
                      IOD.DEPOSIT_ID,
                      IOD.PAYMENT_SEQ_NUM,
                      11         SORT_ORDER
                    FROM
                        INFAR001_OUTBOUND IOD,BATCH B
                    WHERE IOD.BATCH_ID      = B.BATCH_ID
                    AND   B.BATCH_TYPE_CODE = P_BATCH_TYPE_CODE
                    AND   B.BATCH_DATE      = V_BATCH_DATE
                    AND   B.STATUS          = c_BATCH_COMPLETED
                    AND   IOD.STATUS        = c_NEW_STATUS
                    AND   IOD.FS_ROW_ID     = c_PI_ROW_ID
                    UNION
                    SELECT  
                      IOD.FS_ROW_ID                                                ||
                      RPAD(TRIM(IOD.DEPOSIT_BU),5)                                 ||
                      RPAD(TRIM(IOD.DEPOSIT_ID),15)                                ||
                      RPAD(TRIM(IOD.PAYMENT_SEQ_NUM),6)                            ||
                      RPAD(TRIM(IOD.ID_SEQ_NUM),5)                                 ||
                      RPAD(TRIM(IOD.REF_QUALIFIER_CODE),2)                         ||
                      RPAD(TRIM(IOD.REF_VALUE),30)                                 ||
                      CHR(13)   DATA_RECORD,
                      IOD.INFAR001_OUTBOUND_ID,
                      IOD.FS_ROW_ID ROW_ID,
                      IOD.DEPOSIT_ID,
                      IOD.PAYMENT_SEQ_NUM,
                      12         SORT_ORDER
                    FROM
                        INFAR001_OUTBOUND IOD,BATCH B
                    WHERE IOD.BATCH_ID      = B.BATCH_ID
                    AND   B.BATCH_TYPE_CODE = P_BATCH_TYPE_CODE
                    AND   B.BATCH_DATE      = V_BATCH_DATE
                    AND   B.STATUS          = c_BATCH_COMPLETED
                    AND   IOD.STATUS        = c_NEW_STATUS
                    AND   IOD.FS_ROW_ID     = c_IR_ROW_ID
                    UNION
                    SELECT  
                      IOD.FS_ROW_ID                                                ||
                      RPAD(TRIM(IOD.DEPOSIT_BU),5)                                 ||
                      RPAD(TRIM(IOD.DEPOSIT_ID),15)                                ||
                      RPAD(TRIM(IOD.PAYMENT_SEQ_NUM),6)                            ||
                      RPAD(TRIM(IOD.ID_SEQ_NUM),5)                                 ||
                      RPAD(TRIM(IOD.CUST_ID),15)                                   ||
                      CHR(13)   DATA_RECORD,
                      IOD.INFAR001_OUTBOUND_ID,
                      IOD.FS_ROW_ID ROW_ID,
                      IOD.DEPOSIT_ID,
                      IOD.PAYMENT_SEQ_NUM,
                      13         SORT_ORDER
                    FROM
                        INFAR001_OUTBOUND IOD,BATCH B
                    WHERE IOD.BATCH_ID      = B.BATCH_ID
                    AND   B.BATCH_TYPE_CODE = P_BATCH_TYPE_CODE
                    AND   B.BATCH_DATE      = V_BATCH_DATE
                    AND   B.STATUS          = c_BATCH_COMPLETED
                    AND   IOD.STATUS        = c_NEW_STATUS
                    AND   IOD.FS_ROW_ID     = c_CI_ROW_ID
                    UNION
                    SELECT  
                      IOD.FS_ROW_ID                                                                                  ||
                      RPAD(TRIM(IOD.DEPOSIT_BU),5,' ')                                                               ||
                      RPAD(TRIM(IOD.DEPOSIT_ID),15,' ')                                                              ||
                      RPAD(TRIM(IOD.PAYMENT_SEQ_NUM),6,' ')                                                          ||
                      RPAD(TRIM(IOD.DST_SEQ_NUM),6,' ')                                                              ||
                      RPAD(TRIM(IOD.BUSINESS_UNIT_GL),5,' ')                                                         ||
                      RPAD(DECODE(IOD.SPEEDCHART_KEY,NULL,' ',          TRIM(IOD.SPEEDCHART_KEY)),10,' ')            ||
                      RPAD(TO_CHAR(NVL(IOD.MONETARY_AMOUNT ,0),c_AMOUNT_FORMAT),28,CHR(32))                          ||
                      RPAD(DECODE(IOD.ACCOUNT,NULL,' ',                 TRIM(IOD.ACCOUNT)),10,' ')                   ||
                      RPAD(DECODE(IOD.BUSINESS_UNIT_PC,NULL,' ',        TRIM(IOD.BUSINESS_UNIT_PC)),5,' ')           ||
                      RPAD(DECODE(IOD.PROJECT_ID,NULL,' ',              TRIM(IOD.PROJECT_ID)),15,' ')                ||
                      RPAD(DECODE(IOD.ACTIVITY_ID,NULL,' ',             TRIM(IOD.ACTIVITY_ID)),15,' ')               ||
                      RPAD(DECODE(IOD.RESOURCE_TYPE,NULL,' ',           TRIM(IOD.RESOURCE_TYPE)),5,' ')              ||
                      RPAD(DECODE(IOD.RESOURCE_CATEGORY,NULL,' ',       TRIM(IOD.RESOURCE_CATEGORY)),5,' ')          ||
                      RPAD(DECODE(IOD.RESOURCE_SUB_CAT,NULL,' ',        TRIM(IOD.RESOURCE_SUB_CAT)),5,' ')           ||
                      RPAD(DECODE(IOD.ANALYSIS_TYPE,NULL,' ',           TRIM(IOD.ANALYSIS_TYPE)),3,' ')              ||
                      RPAD(DECODE(IOD.OPERATING_UNIT,NULL,' ',          TRIM(IOD.OPERATING_UNIT)),8,' ')             ||      
                      RPAD(DECODE(IOD.PRODUCT,NULL,' ',                 TRIM(IOD.PRODUCT)),6,' ')                    ||
                      RPAD(DECODE(IOD.FUND_CODE,NULL,' ',               TRIM(IOD.FUND_CODE)),9,' ')                  ||
                      RPAD(DECODE(IOD.CLASS_FLD,NULL,' ',               TRIM(IOD.CLASS_FLD)),5,' ')                  ||      
                      RPAD(DECODE(IOD.PROGRAM_CODE,NULL,' ',            TRIM(IOD.PROGRAM_CODE)),10,' ')              ||
                      RPAD(DECODE(IOD.BUDGET_REF,NULL,' ',              TRIM(IOD.BUDGET_REF)),8,' ')                 ||
                      RPAD(DECODE(IOD.AFFILIATE,NULL,' ',               TRIM(IOD.AFFILIATE)),5,' ')                  ||      
                      RPAD(DECODE(IOD.AFFILIATE_INTRA1,NULL,' ',        TRIM(IOD.AFFILIATE_INTRA1)),10,' ')          ||
                      RPAD(DECODE(IOD.AFFILIATE_INTRA2,NULL,' ',        TRIM(IOD.AFFILIATE_INTRA2)),10,' ')          ||      
                      RPAD(DECODE(IOD.CHARTFIELD1,NULL,' ',             TRIM(IOD.CHARTFIELD1)),10,' ')               ||
                      RPAD(DECODE(IOD.CHARTFIELD2,NULL,' ',             TRIM(IOD.CHARTFIELD2)),10,' ')               ||
                      RPAD(DECODE(IOD.CHARTFIELD3,NULL,' ',             TRIM(IOD.CHARTFIELD3)),10,' ')               ||
                      RPAD(DECODE(IOD.ALTACCT,NULL,' ',                 TRIM(IOD.ALTACCT)),10,' ')                   ||
                      RPAD(DECODE(IOD.DEPTID,NULL,' ',                  TRIM(IOD.DEPTID)),10,' ')                    ||
                      RPAD(DECODE(IOD.FUND,NULL,' ',                    TRIM(IOD.FUND)),4,' ')                       ||      
                      RPAD(DECODE(IOD.SUBFUND,NULL,' ',                 TRIM(IOD.SUBFUND)),3,' ')                    ||      
                      RPAD(DECODE(IOD.PROGRAM,NULL,' ',                 TRIM(IOD.PROGRAM)),2,' ')                    ||
                      RPAD(DECODE(IOD.ELEMENT,NULL,' ',                 TRIM(IOD.ELEMENT)),2,' ')                    ||                        
                      RPAD(DECODE(IOD.COMPONENT,NULL,' ',               TRIM(IOD.COMPONENT)),3,' ')                  ||
                      RPAD(DECODE(IOD.TASK,NULL,' ',                    TRIM(IOD.TASK)),3,' ')                       ||
                      RPAD(DECODE(IOD.PCA,NULL,' ',                     TRIM(IOD.PCA)),5,' ')                        ||
                      RPAD(DECODE(IOD.ORG_CODE,NULL,' ',                TRIM(IOD.ORG_CODE)),4,' ')                   ||
                      RPAD(DECODE(IOD.INTERNAL_ORG_STRUCTURE_1,NULL,' ',TRIM(IOD.INTERNAL_ORG_STRUCTURE_1)),10,' ')  ||
                      RPAD(DECODE(IOD.INTERNAL_ORG_STRUCTURE_2,NULL,' ',TRIM(IOD.INTERNAL_ORG_STRUCTURE_2)),10,' ')  ||
                      RPAD(DECODE(IOD.INTERNAL_ORG_STRUCTURE_3,NULL,' ',TRIM(IOD.INTERNAL_ORG_STRUCTURE_3)),10,' ')  ||      
                      RPAD(DECODE(IOD.INTERNAL_ORG_STRUCTURE_4,NULL,' ',TRIM(IOD.INTERNAL_ORG_STRUCTURE_4)),10,' ')  ||
                      RPAD(DECODE(IOD.INTERNAL_ORG_STRUCTURE_5,NULL,' ',TRIM(IOD.INTERNAL_ORG_STRUCTURE_5)),10,' ')  ||
                      RPAD(DECODE(IOD.INDEX_CODE,NULL,' ',              TRIM(IOD.INDEX_CODE)),4,' ')                 ||
                      RPAD(DECODE(IOD.OBJECT_DETAIL,NULL,' ',           TRIM(IOD.OBJECT_DETAIL)),3,' ')              ||
                      RPAD(DECODE(IOD.AGENCY_OBJECT,NULL,' ',           TRIM(IOD.AGENCY_OBJECT)),10,' ')             ||
                      RPAD(DECODE(IOD.SOURCE,NULL,' ',                  TRIM(IOD.SOURCE)),6,' ')                     ||
                      RPAD(DECODE(IOD.AGENCY_SOURCE,NULL,' ',           TRIM(IOD.AGENCY_SOURCE)),10,' ')             ||
                      RPAD(DECODE(IOD.GL_ACCOUNT,NULL,' ',              TRIM(IOD.GL_ACCOUNT)),4,' ')                 ||
                      RPAD(DECODE(IOD.SUBSIDIARY,NULL,' ',              TRIM(IOD.SUBSIDIARY)),8,' ')                 ||
                      RPAD(DECODE(IOD.FUND_SOURCE,NULL,' ',             TRIM(IOD.FUND_SOURCE)),1,' ')                ||
                      RPAD(DECODE(IOD.CHARACTER,NULL,' ',               TRIM(IOD.CHARACTER)),1,' ')                  ||
                      RPAD(DECODE(IOD.METHOD,NULL,' ',                  TRIM(IOD.METHOD)),1,' ')                     ||
                      RPAD(DECODE(IOD.YEAR,NULL,' ',                    TRIM(IOD.YEAR)),4,' ')                       ||
                      RPAD(DECODE(IOD.REFERENCE,NULL,' ',               TRIM(IOD.REFERENCE)),3,' ')                  ||
                      RPAD(DECODE(IOD.FFY,NULL,' ',                     TRIM(IOD.FFY)),4,' ')                        ||
                      RPAD(DECODE(IOD.APPROPRIATION_SYMBOL,NULL,' ',    TRIM(IOD.APPROPRIATION_SYMBOL)),3,' ')       ||
                      RPAD(DECODE(IOD.PROJECT,NULL,' ',                 TRIM(IOD.PROJECT)),10,' ')                   ||
                      RPAD(DECODE(IOD.WORK_PHASE,NULL,' ',              TRIM(IOD.WORK_PHASE)),10,' ')                ||
                      RPAD(DECODE(IOD.MULTIPURPOSE,NULL,' ',            TRIM(IOD.MULTIPURPOSE)),12,' ')              ||
                      RPAD(DECODE(IOD.LOCATION,NULL,' ',                TRIM(IOD.LOCATION)),6,' ')                   ||
                      RPAD(DECODE(IOD.DEPT_USE_1,NULL,' ',              TRIM(IOD.DEPT_USE_1)),20,' ')                ||
                      RPAD(DECODE(IOD.DEPT_USE_2,NULL,' ',              TRIM(IOD.DEPT_USE_2)),20,' ')                ||
                      RPAD(DECODE(IOD.BUDGET_DT,NULL,' ',               TRIM(IOD.BUDGET_DT)),10,' ')                 ||
                      RPAD(DECODE(IOD.LINE_DESCR,NULL,' ',              TRIM(IOD.LINE_DESCR)),30,' ')                ||
                      RPAD(DECODE(IOD.OPEN_ITEM_KEY,NULL,' ',           TRIM(IOD.OPEN_ITEM_KEY)),30,' ')             ||
                      CHR(13)   DATA_RECORD,
                      IOD.INFAR001_OUTBOUND_ID,
                      IOD.FS_ROW_ID ROW_ID,
                      IOD.DEPOSIT_ID,
                      IOD.PAYMENT_SEQ_NUM,
                      14         SORT_ORDER
                    FROM
                        INFAR001_OUTBOUND IOD,BATCH B 
                    WHERE IOD.BATCH_ID      = B.BATCH_ID
                    AND   B.BATCH_TYPE_CODE = P_BATCH_TYPE_CODE
                    AND   B.BATCH_DATE      = V_BATCH_DATE
                    AND   B.STATUS          = c_BATCH_COMPLETED
                    AND   IOD.STATUS        = c_NEW_STATUS
                    AND   IOD.FS_ROW_ID     = c_DJ_ROW_ID
                ) INFAR018_DATA
                ORDER BY
                    INFAR018_DATA.INFAR001_OUTBOUND_ID, 
                    INFAR018_DATA.DEPOSIT_ID,
                    INFAR018_DATA.PAYMENT_SEQ_NUM,
                    INFAR018_DATA.ROW_ID,
                    INFAR018_DATA.SORT_ORDER       
              ) LOOP 
                
                    v_RECORD.INFAR_DATA_RECORD  := i.DATA_RECORD ;
                    
                    PIPE ROW(v_RECORD); 
              
              END LOOP;
        END IF;

      RETURN; 
      
    EXCEPTION
        WHEN OTHERS THEN
                LOG_CARS_ERROR(
                    p_errorLevel    => 1,
                    p_severity      => c_HIGH_SEVERITY,
                    p_errorDetail   => 'FISCAL INFAR018 Interface data file generation for the batch type '||P_BATCH_TYPE_CODE||' failed',
                    p_errorCode     => 5002,
                    p_errorMessage  => SQLERRM,
                    p_dataSource    => c_CARS_DB
                    );
            RETURN;

    END EXTRACT_INFAR018_DATA;
    
    FUNCTION GET_FISCAL_BATCH_ID( 
                            P_BATCH_STATUS      BATCH.STATUS%TYPE,
                            P_BATCH_DATE        BATCH.CREATED_DATE%TYPE,
                            P_BATCH_TYPE_CODE   BATCH.BATCH_TYPE_CODE%TYPE
                           ) RETURN BATCH.BATCH_ID%TYPE AS

    V_BATCH_ID BATCH.BATCH_ID%TYPE; 

    BEGIN
            
        DBMS_OUTPUT.PUT_LINE('GET_FISCAL_BATCH_ID '
                                ||' P_BATCH_STATUS = '   ||P_BATCH_STATUS 
                                ||' P_BATCH_DATE = '     ||P_BATCH_DATE
                                ||' P_BATCH_TYPE_CODE = '||P_BATCH_TYPE_CODE
                                );
                                    
        IF (P_BATCH_TYPE_CODE IS NOT NULL) AND (P_BATCH_DATE IS NOT NULL) AND (P_BATCH_STATUS IS NOT NULL) THEN 

            SELECT  B.BATCH_ID
            INTO    V_BATCH_ID
            FROM    BATCH B
            WHERE   B.STATUS            = C_BATCH_COMPLETED
            AND     B.BATCH_TYPE_CODE   = P_BATCH_TYPE_CODE
            AND     B.BATCH_DATE        = TO_CHAR(P_BATCH_DATE , 'RRRRMMDD') ;
                            
            DBMS_OUTPUT.PUT_LINE('The Fiscal Batch key is '||v_BATCH_ID||' for the batch type '||P_BATCH_TYPE_CODE||' date '||P_BATCH_DATE||' and batch status  '||C_BATCH_COMPLETED); 
            
            RETURN V_BATCH_ID;
            
        END IF;

    EXCEPTION
        WHEN OTHERS THEN 
            DBMS_OUTPUT.PUT_LINE('The Fiscal Batch key is not found for the batch type '||P_BATCH_TYPE_CODE||' date '||P_BATCH_DATE||' and batch status  '||C_BATCH_COMPLETED); 
            
            RETURN V_BATCH_ID;
            
    END GET_FISCAL_BATCH_ID;
    
    PROCEDURE UPD_ACCTG_EVENT_STATUS(
                P_BATCH_ID          BATCH.BATCH_ID%TYPE,
                P_AE_FROM_STATUS    ACCOUNTING_ENTRY_STATUS.FS_PROCESS_STATUS%TYPE,
                P_AE_TO_STATUS      ACCOUNTING_ENTRY_STATUS.FS_PROCESS_STATUS%TYPE,
                P_ACTION            BATCH.DATA_SOURCE_CODE%TYPE,
                P_SUCCESS       OUT VARCHAR2,
                P_MESSAGE       OUT VARCHAR2
                ) IS

       V_SUCCESS_FLAG   VARCHAR2(1)      := c_YES;
       V_MESSAGE        VARCHAR2(500);
       
    BEGIN
            
        DBMS_OUTPUT.PUT_LINE('UPD_ACCTG_EVENT_STATUS '
                                ||' Batch Id = '                        ||P_BATCH_ID 
                                ||' Accounting Entry From Status = '    ||P_AE_FROM_STATUS
                                ||' Accounting Entry To Status = '      ||P_AE_TO_STATUS
                                ||' Action  = '                         ||P_ACTION
                                );

        IF (P_BATCH_ID IS NOT NULL) THEN
    
                IF (P_ACTION = c_INFAR006_BATCH) THEN
                 
                    UPDATE  ACCOUNTING_ENTRY_STATUS AES
                    SET     AES.FS_PROCESS_STATUS= P_AE_TO_STATUS, 
                            AES.MODIFIED_BY      = c_USER,
                            AES.MODIFIED_DATE    = SYSDATE
                    WHERE   EXISTS (SELECT ACCTG_ENTRY_ID 
                                    FROM   INFAR006_OUTBOUND IO
                                    WHERE  IO.BATCH_ID          = P_BATCH_ID
                                    AND    IO.ACCTG_ENTRY_ID    = AES.ACCTG_ENTRY_ID
                                    )  
                    AND   AES.FS_PROCESS_STATUS = P_AE_FROM_STATUS;

                    V_MESSAGE := SQL%ROWCOUNT||' records of ACCOUNTING_ENTRY_STATUS table of batch type '||P_ACTION||' updated with batch id '||P_BATCH_ID||' and status '||P_AE_TO_STATUS;

                    DBMS_OUTPUT.PUT_LINE(
                                            ' P_BATCH_ID = '    ||P_BATCH_ID        ||
                                            ' P_ACTION = '      ||P_ACTION          || 
                                            ' V_SUCCESS_FLAG = '||V_SUCCESS_FLAG||' '|| 
                                            V_MESSAGE
                                            );

                ELSIF (P_ACTION = c_INFAR001_BATCH) THEN
                 
                    UPDATE  ACCOUNTING_ENTRY_STATUS AES
                    SET     AES.FS_PROCESS_STATUS= P_AE_TO_STATUS, 
                            AES.MODIFIED_BY      = c_USER,
                            AES.MODIFIED_DATE    = SYSDATE
                    WHERE   EXISTS (SELECT ACCTG_ENTRY_ID 
                                    FROM   INFAR001_OUTBOUND IO
                                    WHERE  IO.BATCH_ID          = P_BATCH_ID
                                    AND    IO.ACCTG_ENTRY_ID    = AES.ACCTG_ENTRY_ID
                                    )  
                    AND   AES.FS_PROCESS_STATUS = P_AE_FROM_STATUS;

                    V_MESSAGE := SQL%ROWCOUNT||' records of ACCOUNTING_ENTRY_STATUS table of batch type '||P_ACTION||' updated with batch id '||P_BATCH_ID||' and status '||P_AE_TO_STATUS;
                                        
                ELSIF (P_ACTION = c_INFAR018_BATCH) THEN
                 
                    UPDATE  ACCOUNTING_ENTRY_STATUS AES
                    SET     AES.FS_PROCESS_STATUS= P_AE_TO_STATUS, 
                            AES.MODIFIED_BY      = c_USER,
                            AES.MODIFIED_DATE    = SYSDATE
                    WHERE   EXISTS (SELECT ACCTG_ENTRY_ID 
                                    FROM   INFAR001_OUTBOUND IO
                                    WHERE  IO.BATCH_ID          = P_BATCH_ID
                                    AND    IO.ACCTG_ENTRY_ID    = AES.ACCTG_ENTRY_ID
                                    )  
                    AND   AES.FS_PROCESS_STATUS = P_AE_FROM_STATUS;

                    V_MESSAGE := SQL%ROWCOUNT||' records of ACCOUNTING_ENTRY_STATUS table of batch type '||P_ACTION||' updated with batch id '||P_BATCH_ID||' and status '||P_AE_TO_STATUS;
                                        

                ELSE
                    
                    V_SUCCESS_FLAG     := c_NO;
                    V_MESSAGE          :=  
                                          ' P_BATCH_ID = '      ||P_BATCH_ID
                                        ||' P_AE_FROM_STATUS = '||P_AE_FROM_STATUS
                                        ||' P_AE_TO_STATUS = '  ||P_AE_TO_STATUS
                                        ||' P_ACTION = '        ||P_ACTION||' Parameter value provided is invalid'
                                        ;

                    DBMS_OUTPUT.PUT_LINE(
                                            ' V_SUCCESS_FLAG = '||V_SUCCESS_FLAG||' ' 
                                            ||V_MESSAGE
                                            ); 
                END IF;

        ELSE
                V_SUCCESS_FLAG     := c_NO;
                V_MESSAGE          := 'One of the Parameter value to the procedure is not provided' 
                                    ||' P_BATCH_ID = '      ||P_BATCH_ID
                                    ||' P_ACTION = '        ||P_ACTION
                                    ||' P_AE_FROM_STATUS = '||P_AE_FROM_STATUS
                                    ||' P_AE_TO_STATUS = '  ||P_AE_TO_STATUS;

        END IF;

        P_SUCCESS     := V_SUCCESS_FLAG;
        P_MESSAGE     := V_MESSAGE;


        DBMS_OUTPUT.PUT_LINE(
                                ' V_SUCCESS_FLAG = '||V_SUCCESS_FLAG||' '
                                ||V_MESSAGE
                                ); 
    EXCEPTION
        WHEN OTHERS THEN 

                V_SUCCESS_FLAG  := c_NO;
                V_MESSAGE       := 'Failure occured in UPD_ACCTG_EVENT_STATUS :' ||SQLERRM;

                P_SUCCESS       := V_SUCCESS_FLAG;
                P_MESSAGE       := V_MESSAGE;

                DBMS_OUTPUT.PUT_LINE(
                                        ' V_SUCCESS_FLAG = '||V_SUCCESS_FLAG||' '
                                        ||V_MESSAGE
                                        ); 
    END UPD_ACCTG_EVENT_STATUS; 
    
    PROCEDURE UPD_FISCAL_BATCH( 
                            P_BATCH_ID          BATCH.BATCH_ID%TYPE, 
                            P_BATCH_STATUS      BATCH.STATUS%TYPE,
                            P_BATCH_DATE        BATCH.CREATED_DATE%TYPE,
                            P_BATCH_TYPE_CODE   BATCH.BATCH_TYPE_CODE%TYPE,
                            P_BATCH_FILE_NAME   BATCH.BATCH_TYPE_CODE%TYPE,
                            P_STATUS            OUT VARCHAR2,
                            P_MESSAGE           OUT VARCHAR2
                            ) AS

    V_ERROR_CODE        CARS_ERROR_LOG.ERROR_CODE%TYPE;
    V_ERROR_MESSAGE     CARS_ERROR_LOG.ERROR_MESSAGE%TYPE;
            
    BEGIN
        DBMS_OUTPUT.PUT_LINE('[UPD_FISCAL_BATCH]: P_BATCH_TYPE_CODE = '||P_BATCH_TYPE_CODE||' P_BATCH_ID = '||P_BATCH_ID||
                                ' P_BATCH_STATUS = '||P_BATCH_STATUS||' P_BATCH_DATE = '||P_BATCH_DATE||' P_BATCH_FILE_NAME = '||P_BATCH_FILE_NAME);
                        
        IF (P_BATCH_ID IS NOT NULL) AND (P_BATCH_TYPE_CODE IS NOT NULL) AND (P_BATCH_STATUS IS NOT NULL) THEN 

            UPDATE  BATCH B
            SET     B.STATUS            = P_BATCH_STATUS,
                    B.NOTE_TEXT         = B.NOTE_TEXT||' '||P_BATCH_FILE_NAME,
                    B.MODIFIED_BY       = C_USER,
                    B.MODIFIED_DATE     = SYSDATE
            WHERE   B.BATCH_ID          = P_BATCH_ID
            AND     B.STATUS            = C_BATCH_COMPLETED
            AND     B.BATCH_TYPE_CODE   = P_BATCH_TYPE_CODE;
                            
            V_ERROR_MESSAGE := 'The Batch table with type '||P_BATCH_TYPE_CODE||' date '||P_BATCH_DATE||' and key '||P_BATCH_ID||' '||SQL%ROWCOUNT||' records updated with status '||P_BATCH_STATUS;

            P_STATUS    := c_YES;
            P_MESSAGE   := P_BATCH_TYPE_CODE||' Outbound records updated with status '||P_BATCH_STATUS;

        ELSE
            V_ERROR_MESSAGE := '[UPD_FISCAL_BATCH] One or more input parameter values is missing.'
                                ||' P_BATCH_TYPE_CODE = '   ||P_BATCH_TYPE_CODE
                                ||' P_BATCH_ID = '          ||P_BATCH_ID
                                ||' P_BATCH_STATUS = '      ||P_BATCH_STATUS
                                ||' P_BATCH_DATE = '        ||P_BATCH_DATE
                                ||' P_BATCH_FILE_NAME = '   ||P_BATCH_FILE_NAME
                                ;
            P_STATUS    := c_NO;
            P_MESSAGE   := V_ERROR_MESSAGE; 
            
        END IF;

            DBMS_OUTPUT.PUT_LINE('Status '||P_STATUS||' '||V_ERROR_MESSAGE||' '); 

    EXCEPTION
        WHEN OTHERS THEN 
            V_ERROR_MESSAGE := 'The Batch table with type '||P_BATCH_TYPE_CODE||' date '||P_BATCH_DATE||' and key '||P_BATCH_ID||' could not be updated with status '||P_BATCH_STATUS;

            P_STATUS    := c_NO;
            P_MESSAGE   := V_ERROR_MESSAGE||'. '||SQLERRM;
 
            DBMS_OUTPUT.PUT_LINE('Status '||P_STATUS||' '||V_ERROR_MESSAGE||' ' ||SQLERRM); 
           
    END UPD_FISCAL_BATCH;

    PROCEDURE UPD_INTERFACE_DATA( 
                            P_BATCH_ID          INFAR006_OUTBOUND.BATCH_ID%TYPE, 
                            P_RECORD_STATUS     INFAR006_OUTBOUND.STATUS%TYPE,
                            P_SUBPROGRAM_GRP    PROGRAM_UNIT.PROGRAM_UNIT_CODE%TYPE,
                            P_FS_INTERFACE      BATCH.BATCH_TYPE_CODE%TYPE,
                            P_BATCH_TYPE_CODE   BATCH.BATCH_TYPE_CODE%TYPE,
                            P_STATUS            OUT VARCHAR2,
                            P_MESSAGE           OUT VARCHAR2
                            ) AS

    V_SUBPROGRAM_GRP    BATCH.BATCH_TYPE_CODE%TYPE;
    V_FS_INTERFACE      BATCH.BATCH_TYPE_CODE%TYPE;
    
    V_ERROR_CODE        CARS_ERROR_LOG.ERROR_CODE%TYPE;
    V_ERROR_MESSAGE     CARS_ERROR_LOG.ERROR_MESSAGE%TYPE;
            
    BEGIN
                                    
        DBMS_OUTPUT.PUT_LINE('UPD_INTERFACE_DATA:'||
                                ' P_BATCH_TYPE_CODE = ' ||P_BATCH_TYPE_CODE ||
                                ' P_BATCH_ID = '        ||P_BATCH_ID        ||
                                ' P_RECORD_STATUS = '   ||P_RECORD_STATUS   ||
                                ' P_SUBPROGRAM_GRP = '  ||P_SUBPROGRAM_GRP  ||
                                ' P_FS_INTERFACE = '    ||P_FS_INTERFACE
                                );

        IF (P_BATCH_ID IS NOT NULL) AND (P_BATCH_TYPE_CODE IS NOT NULL) AND (P_RECORD_STATUS IS NOT NULL) THEN 
                   
            -- Verify if the Batch is for Subprogram Group like DWC, DLSE or CARS
            CASE
                WHEN (P_SUBPROGRAM_GRP IN (c_PU_CARS,c_PU_DLSE,c_PU_DWC))  THEN     V_SUBPROGRAM_GRP := P_SUBPROGRAM_GRP;

                ELSE V_SUBPROGRAM_GRP := NULL;

            END CASE;       

            -- Verify if the Batch is for interface file like INFAR006 and INFAR001
            CASE
                WHEN (P_FS_INTERFACE IN (c_INFAR006_BATCH, c_INFAR001_BATCH, c_INFAR018_BATCH)) THEN V_FS_INTERFACE := P_FS_INTERFACE;

                ELSE V_FS_INTERFACE := NULL;

            END CASE;       

            DBMS_OUTPUT.PUT_LINE('P_BATCH_TYPE_CODE = '||P_BATCH_TYPE_CODE||' V_FS_INTERFACE = '||V_FS_INTERFACE||' V_SUBPROGRAM_GRP = '||V_SUBPROGRAM_GRP);

        
            -- CARS system Integrated subprogram units 
            IF (V_SUBPROGRAM_GRP = c_PU_CARS) AND (V_FS_INTERFACE = c_INFAR006_BATCH)  THEN
                    
                UPDATE  INFAR006_OUTBOUND I6O
                SET     I6O.STATUS          = P_RECORD_STATUS,
                        I6O.MODIFIED_BY     = C_USER,
                        I6O.MODIFIED_DATE   = SYSDATE
                WHERE   I6O.BATCH_ID        = P_BATCH_ID
                AND     I6O.STATUS          = C_NEW_STATUS ;

                V_ERROR_MESSAGE := 'The INFAR006_OUTBOUND table records with batch  '||P_BATCH_ID||'. Total of '||SQL%ROWCOUNT||' records updated with status '||P_RECORD_STATUS;
            
            ELSIF (V_SUBPROGRAM_GRP = c_PU_CARS) AND (V_FS_INTERFACE = c_INFAR001_BATCH)  THEN
                    
                UPDATE  INFAR001_OUTBOUND I1O
                SET     I1O.STATUS          = P_RECORD_STATUS,
                        I1O.MODIFIED_BY     = C_USER,
                        I1O.MODIFIED_DATE   = SYSDATE
                WHERE   I1O.BATCH_ID        = P_BATCH_ID
                AND     I1O.STATUS          = C_NEW_STATUS ;

                V_ERROR_MESSAGE := 'The INFAR001_OUTBOUND table records with batch  '||P_BATCH_ID||'. Total of '||SQL%ROWCOUNT||' records updated with status '||P_RECORD_STATUS;

            ELSIF (V_SUBPROGRAM_GRP = c_PU_CARS) AND (V_FS_INTERFACE = c_INFAR018_BATCH)  THEN
                    
                UPDATE  INFAR001_OUTBOUND I1O
                SET     I1O.STATUS          = P_RECORD_STATUS,
                        I1O.MODIFIED_BY     = C_USER,
                        I1O.MODIFIED_DATE   = SYSDATE
                WHERE   I1O.BATCH_ID        = P_BATCH_ID
                AND     I1O.STATUS          = C_NEW_STATUS ;

                V_ERROR_MESSAGE := 'The INFAR001_OUTBOUND table records for AR018 data with batch  '||P_BATCH_ID||'. Total of '||SQL%ROWCOUNT||' records updated with status '||P_RECORD_STATUS;

            END IF;   

            P_STATUS    := c_YES;
            P_MESSAGE   := V_ERROR_MESSAGE; 

        ELSE
            V_ERROR_MESSAGE := '[UPD_INTERFACE_DATA] One or more input parameter values is missing.'
                                ||' P_BATCH_TYPE_CODE = '   ||P_BATCH_TYPE_CODE
                                ||' P_BATCH_ID = '          ||P_BATCH_ID
                                ||' P_RECORD_STATUS = '     ||P_RECORD_STATUS
                                ||' P_SUBPROGRAM_GRP = '    ||P_SUBPROGRAM_GRP
                                ||' P_FS_INTERFACE = '      ||P_FS_INTERFACE
                                ;
            P_STATUS    := c_NO;
            P_MESSAGE   := V_ERROR_MESSAGE; 

        END IF;

        DBMS_OUTPUT.PUT_LINE('Status '||P_STATUS||' V_ERROR_MESSAGE = '||V_ERROR_MESSAGE); 

    EXCEPTION
        WHEN OTHERS THEN 
            V_ERROR_MESSAGE := 'FISCal Interface table '||P_FS_INTERFACE||' with type '||P_BATCH_TYPE_CODE||' and key '||P_BATCH_ID||' could not be updated with status '||P_RECORD_STATUS;          

            P_STATUS    := c_NO;
            P_MESSAGE   := V_ERROR_MESSAGE||' ' ||SQLERRM;
            
           DBMS_OUTPUT.PUT_LINE('Status '||P_STATUS||' '||V_ERROR_MESSAGE||' ' ||SQLERRM); 

    END UPD_INTERFACE_DATA;  

     PROCEDURE UPD_FISCAL_DATA_STATUS (
                            P_BATCH_TYPE_CODE   BATCH.BATCH_TYPE_CODE%TYPE,
                            P_BATCH_DATE        BATCH.CREATED_DATE%TYPE,
                            P_BATCH_STATUS      BATCH.STATUS%TYPE,
                            P_BATCH_FILE_NAME   BATCH.BATCH_TYPE_CODE%TYPE
                            )  AS

    V_BATCH_ID          BATCH.BATCH_ID%TYPE;
    V_BATCH_STATUS      BATCH.STATUS%TYPE;
    V_BATCH_DATE        BATCH.CREATED_DATE%TYPE;
    V_SUBPROGRAM_GRP    BATCH.BATCH_TYPE_CODE%TYPE;
    V_FS_INTERFACE      BATCH.BATCH_TYPE_CODE%TYPE;        

    V_AE_STATUS         ACCOUNTING_ENTRY_STATUS.FS_PROCESS_STATUS%TYPE;  -- FAILED OR TRANSMITTED
    V_ACTION            VARCHAR2(25);
    V_STATUS            VARCHAR2(1)                     := C_YES;
    
    V_SEVERITY          CARS_ERROR_LOG.SEVERITY%TYPE    := c_LOW_SEVERITY;
    V_ERROR_LEVEL       CARS_ERROR_LOG.ERROR_LEVEL%TYPE := 1;
    V_MESSAGE           CARS_ERROR_LOG.ERROR_DETAIL%TYPE;
    V_LOG_TEXT          CARS_ERROR_LOG.ERROR_DETAIL%TYPE;    
    V_ERROR_CODE        CARS_ERROR_LOG.ERROR_CODE%TYPE;
    V_ERROR_DETAIL      CARS_ERROR_LOG.ERROR_DETAIL%TYPE;
           
    BEGIN
        
        IF  (P_BATCH_TYPE_CODE IS NULL) OR (P_BATCH_STATUS IS NULL) OR (P_BATCH_DATE IS NULL) OR (P_BATCH_FILE_NAME IS NULL) THEN 
            V_STATUS        := c_NO;
            V_MESSAGE       := 'One or more input parameter values are not passed to the procedure.';
            V_SEVERITY      := c_HIGH_SEVERITY;
            V_ERROR_LEVEL   := 3;            
        END IF;

        IF (P_BATCH_DATE IS NOT NULL) THEN
            V_BATCH_DATE    := TRIM(P_BATCH_DATE);
        END IF;
        
        DBMS_OUTPUT.PUT_LINE('[UPD_FISCAL_DATA_STATUS]'||
                                ' P_BATCH_TYPE_CODE = ' ||P_BATCH_TYPE_CODE ||
                                ' P_BATCH_DATE = '      ||P_BATCH_DATE      ||
                                ' V_BATCH_DATE = '      ||V_BATCH_DATE      ||
                                ' P_BATCH_STATUS = '    ||P_BATCH_STATUS    ||
                                ' P_BATCH_FILE_NAME = ' ||P_BATCH_FILE_NAME ||
                                ' V_STATUS = '          ||V_STATUS          ||
                                ' V_MESSAGE = '         ||V_MESSAGE
                                );

        V_LOG_TEXT := V_LOG_TEXT||' [P_BATCH_TYPE_CODE] '   ||P_BATCH_TYPE_CODE
                                ||' [P_BATCH_DATE] '        ||P_BATCH_DATE
                                ||' [P_BATCH_STATUS] '      ||P_BATCH_STATUS
                                ||' [P_BATCH_FILE_NAME] '   ||P_BATCH_FILE_NAME
                                ||' [V_STATUS] '            ||V_STATUS
                                ||' [V_MESSAGE] '           ||V_MESSAGE
                                ;

        IF   (V_STATUS = C_YES) THEN
                

            -- Set the Status of the Accounting Entry Status table records and the INFAR006 and INFAR001 record status
            CASE
                WHEN (P_BATCH_STATUS = c_BATCH_TRANSMIT) THEN  V_AE_STATUS := c_AE_TRANSMITTED; V_BATCH_STATUS := c_BATCH_TRANSMIT;

                WHEN (P_BATCH_STATUS = c_BATCH_ERROR) THEN     V_AE_STATUS := c_AE_FAILED;      V_BATCH_STATUS := c_BATCH_ERROR; 

                ELSE V_AE_STATUS := NULL; V_BATCH_STATUS := NULL;

            END CASE;

           -- Verify if the Batch is for interface file like INFAR006 and INFAR001
            CASE
                WHEN INSTR(P_BATCH_TYPE_CODE,c_INFAR006_BATCH) > 0 THEN     V_ACTION := c_INFAR006_BATCH; V_FS_INTERFACE := c_INFAR006_BATCH;

                WHEN INSTR(P_BATCH_TYPE_CODE,c_INFAR001_BATCH) > 0 THEN     V_ACTION := c_INFAR001_BATCH; V_FS_INTERFACE := c_INFAR001_BATCH; 

                WHEN INSTR(P_BATCH_TYPE_CODE,c_INFAR018_BATCH) > 0 THEN     V_ACTION := c_INFAR018_BATCH; V_FS_INTERFACE := c_INFAR018_BATCH; 

                ELSE V_ACTION := NULL; V_FS_INTERFACE := NULL;

            END CASE;

            -- Verify if the Batch is for Subprogram Group like DWC, DLSE or CARS
            CASE
                WHEN INSTR(P_BATCH_TYPE_CODE,c_PU_CARS) > 0 THEN  V_SUBPROGRAM_GRP := c_PU_CARS;

                WHEN INSTR(P_BATCH_TYPE_CODE,c_PU_DLSE) > 0 THEN  V_SUBPROGRAM_GRP := c_PU_DLSE;

                WHEN INSTR(P_BATCH_TYPE_CODE,c_PU_DWC)  > 0 THEN  V_SUBPROGRAM_GRP := c_PU_DWC; 

                ELSE V_SUBPROGRAM_GRP := NULL;

            END CASE; 


            IF  (P_BATCH_TYPE_CODE IS NOT NULL) THEN 

                V_BATCH_ID := GET_FISCAL_BATCH_ID( 
                                    P_BATCH_STATUS      => C_BATCH_COMPLETED,
                                    P_BATCH_DATE        => P_BATCH_DATE,
                                    P_BATCH_TYPE_CODE   => P_BATCH_TYPE_CODE
                                    );
            END IF;
         
            DBMS_OUTPUT.PUT_LINE('Get FISCAL Batch ID, P_BATCH_TYPE_CODE = '||P_BATCH_TYPE_CODE||
                                    ' V_BATCH_ID = '    ||V_BATCH_ID||
                                    ' P_BATCH_STATUS = '||P_BATCH_STATUS||
                                    ' V_STATUS = '      ||V_STATUS||
                                    ' V_MESSAGE = '     ||V_MESSAGE
                                    );
                 

            IF  (V_BATCH_ID IS NULL) OR (V_AE_STATUS IS NULL) OR (V_BATCH_STATUS IS NULL) AND (V_ACTION IS NULL) OR (V_SUBPROGRAM_GRP IS NULL) AND (V_FS_INTERFACE IS NULL) THEN 
                V_STATUS        := c_NO;
                V_MESSAGE       := 'One or more variable are not set or have invalid value.';
                V_SEVERITY      := c_HIGH_SEVERITY;
                V_ERROR_LEVEL   := 3;            
            END IF;

            DBMS_OUTPUT.PUT_LINE( ' V_BATCH_ID = '          ||V_BATCH_ID
                                    ||' P_BATCH_STATUS = '      ||P_BATCH_STATUS
                                    ||' V_AE_STATUS = '         ||V_AE_STATUS
                                    ||' V_BATCH_STATUS = '      ||V_BATCH_STATUS
                                    ||' V_ACTION = '            ||V_ACTION
                                    ||' V_FS_INTERFACE = '      ||V_FS_INTERFACE
                                    ||' V_SUBPROGRAM_GRP = '    ||V_SUBPROGRAM_GRP
                                    );

            V_LOG_TEXT := V_LOG_TEXT||' [V_BATCH_ID] '      ||V_BATCH_ID
                                    ||' [V_AE_STATUS] '     ||V_AE_STATUS
                                    ||' [V_BATCH_STATUS] '  ||V_BATCH_STATUS
                                    ||' [V_ACTION] '        ||V_ACTION
                                    ||' [V_FS_INTERFACE] '  ||V_FS_INTERFACE
                                    ||' [V_SUBPROGRAM_GRP] '||V_SUBPROGRAM_GRP
                                    ||' [V_STATUS] '        ||V_STATUS
                                    ||' [V_MESSAGE] '       ||V_MESSAGE;
        END IF;

        -- Update Accounting Entry Status table for CARS group only                                
        IF (V_BATCH_ID IS NOT NULL)  AND (P_BATCH_TYPE_CODE IS NOT NULL) AND 
           (V_STATUS = C_YES) AND (INSTR(P_BATCH_TYPE_CODE,c_PU_CARS) > 0) THEN


            DBMS_OUTPUT.PUT_LINE( ' V_BATCH_ID = '         ||V_BATCH_ID
                                    ||' P_BATCH_TYPE_CODE = '  ||P_BATCH_TYPE_CODE
                                    ||' P_AE_FROM_STATUS = '   ||c_AE_BATCHED
                                    ||' V_AE_STATUS = '        ||V_AE_STATUS
                                    ||' V_ACTION = '           ||V_ACTION
                                     );

            UPD_ACCTG_EVENT_STATUS(
                            P_BATCH_ID          => V_BATCH_ID, 
                            P_AE_FROM_STATUS    => c_AE_BATCHED,
                            P_AE_TO_STATUS      => V_AE_STATUS,
                            P_ACTION            => V_ACTION,
                            P_SUCCESS           => V_STATUS,
                            P_MESSAGE           => V_MESSAGE
                            );    

            IF (V_STATUS = C_NO) THEN
                V_SEVERITY      := c_HIGH_SEVERITY;
                V_ERROR_LEVEL   := 3;            
    
            END IF;

            V_LOG_TEXT := V_LOG_TEXT||' [UPD_ACCTG_EVENT_STATUS] '
                                    ||' [V_ACTION] '            ||V_ACTION
                                    ||' [P_AE_FROM_STATUS] '    ||c_AE_BATCHED
                                    ||' [V_AE_STATUS] '         ||V_AE_STATUS
                                    ||' [V_STATUS] '            ||V_STATUS
                                    ||' [V_MESSAGE] '           ||V_MESSAGE;

        END IF;

        DBMS_OUTPUT.PUT_LINE('Update Accounting Event Status table, P_BATCH_TYPE_CODE = '||P_BATCH_TYPE_CODE
                                ||' V_BATCH_ID = '      ||V_BATCH_ID
                                ||' P_BATCH_STATUS = '  ||P_BATCH_STATUS
                                ||' V_AE_STATUS = '     ||V_AE_STATUS
                                ||' V_ACTION = '        ||V_ACTION
                                ||' V_STATUS = '        ||V_STATUS
                                ||' V_MESSAGE = '       ||V_MESSAGE
                                );
        
        IF (V_BATCH_ID IS NOT NULL) AND (V_FS_INTERFACE IS NOT NULL) AND (V_SUBPROGRAM_GRP IS NOT NULL) AND (P_BATCH_TYPE_CODE IS NOT NULL)THEN

            UPD_INTERFACE_DATA( 
                        P_BATCH_ID          => V_BATCH_ID, 
                        P_RECORD_STATUS     => CASE WHEN V_STATUS = C_YES THEN V_AE_STATUS ELSE c_AE_FAILED END,
                        P_SUBPROGRAM_GRP    => V_SUBPROGRAM_GRP,
                        P_FS_INTERFACE      => V_FS_INTERFACE,
                        P_BATCH_TYPE_CODE   => P_BATCH_TYPE_CODE,
                        P_STATUS            => V_STATUS,
                        P_MESSAGE           => V_MESSAGE
                        );    
                            
            IF (V_STATUS = C_NO) THEN
                V_SEVERITY      := c_HIGH_SEVERITY;
                V_ERROR_LEVEL   := 3;            
            
            END IF;

            V_LOG_TEXT := V_LOG_TEXT||' [UPD_INTERFACE_DATA] '
                                    ||' [V_STATUS] '        ||V_STATUS
                                    ||' [V_MESSAGE] '       ||V_MESSAGE;

        END IF;

        DBMS_OUTPUT.PUT_LINE('Update FISCAL Interface table, P_BATCH_TYPE_CODE = '||P_BATCH_TYPE_CODE
                                ||' V_BATCH_ID = '      ||V_BATCH_ID
                                ||' P_BATCH_STATUS = '  ||P_BATCH_STATUS
                                ||' V_STATUS = '        ||V_STATUS
                                ||' V_MESSAGE = '       ||V_MESSAGE
                                );

        IF (V_BATCH_ID IS NOT NULL) AND (V_BATCH_STATUS IS NOT NULL) AND (P_BATCH_TYPE_CODE IS NOT NULL) THEN --(P_BATCH_DATE IS NOT NULL) AND

            UPD_FISCAL_BATCH( 
                                P_BATCH_ID          => V_BATCH_ID, 
                                P_BATCH_STATUS      => CASE WHEN V_STATUS = C_YES THEN V_BATCH_STATUS ELSE c_BATCH_ERROR END,
                                P_BATCH_DATE        => P_BATCH_DATE,
                                P_BATCH_TYPE_CODE   => P_BATCH_TYPE_CODE,
                                P_BATCH_FILE_NAME   => P_BATCH_FILE_NAME,
                                P_STATUS            => V_STATUS,
                                P_MESSAGE           => V_MESSAGE
                                );    

            IF (V_STATUS = C_NO) THEN
                V_SEVERITY      := c_HIGH_SEVERITY;
                V_ERROR_LEVEL   := 3;            
            
            END IF;
            
            V_LOG_TEXT := V_LOG_TEXT||' [UPD_FISCAL_BATCH] '
                                    ||' [V_STATUS] '        ||V_STATUS
                                    ||' [V_MESSAGE] '       ||V_MESSAGE;
        END IF;

        DBMS_OUTPUT.PUT_LINE('Update FISCAL Batch table, P_BATCH_TYPE_CODE = '||P_BATCH_TYPE_CODE||
                                  ' V_BATCH_ID = '      ||V_BATCH_ID
                                ||' P_BATCH_STATUS = '  ||P_BATCH_STATUS
                                ||' V_STATUS = '        ||V_STATUS
                                ||' V_MESSAGE = '       ||V_MESSAGE
                                );
              
        IF (V_ERROR_LEVEL = 3) THEN
            V_ERROR_CODE    := 5001;
            V_ERROR_DETAIL  := 'FISCAL '||V_ACTION||' Interface data File generation failed';            
    
        ELSE
            V_ERROR_CODE    := '0000';
            V_ERROR_DETAIL  := 'FISCAL '||V_ACTION||' Interface data File generation was successful';            
        END IF;

        LOG_CARS_ERROR(
            p_errorLevel    => V_ERROR_LEVEL,
            p_severity      => V_SEVERITY,
            p_errorDetail   => V_ERROR_DETAIL,
            p_errorCode     => V_ERROR_CODE,
            p_errorMessage  => SUBSTR(V_LOG_TEXT,1,2500),
            p_dataSource    => c_CARS_DB
            );

    END UPD_FISCAL_DATA_STATUS;
        
END FS_DATA_FILE_PKG;
/