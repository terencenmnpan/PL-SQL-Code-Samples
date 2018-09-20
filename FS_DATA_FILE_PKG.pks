CREATE OR REPLACE PACKAGE FS_DATA_FILE_PKG AS
/******************************************************************************
   NAME:       FS_DATA_FILE_PKG
   PURPOSE:

   REVISIONS:
   Ver        Date        Author           Description
   ---------  ----------  ---------------  ------------------------------------
   1.0        02/07/2018  Vinaykumar Patil 1. Created for Financial Information System of California Interface
                                              Added Functions and Procedures
                                           2.EXTRACT_INFAR006_DATA Function
              02/22/2018  Vinaykumar Patil 1.Added Constants and modified the functions  
              02/25/2018  Vinaykumar Patil 1.Added procedure UPD_ACCTG_EVENT_STATUS                                          
              03/2/2018   Vinaykumar Patil 1.Added procedure LOG_CARS_ERROR and FS_DATA_FILE_PROCESSING  
              04/2/2018   Vinaykumar Patil 1.Added overloaded procedures EXTRACT_INFAR006_DATA, EXTRACT_INFAR001_DATA 
              04/3/2018   Vinaykumar Patil 1.Added procedures UPD_FISCAL_BATCH, UPD_INTERFACE_DATA 
              04/4/2018   Vinaykumar Patil 1.Added procedures GET_FISCAL_BATCH_ID and modified UPD_ACCTG_EVENT_STATUS
              04/05/2015  Vinaykumar Patil 1 Added procedure UPD_FISCAL_DATA_STATUS
              04/09/2018  Vinaykumar Patil 1 Modified the procedure to remove extra logic to check setup vs Adjustment
                                           2 Added parameter to INFAR006 Data File generation procedure
                                           3 Removed FS_DATA_FILE_PROCESSING procedure
              04/10/2018  Vinaykumar Patil 1 Removed UPD_INTERFACE_DATA, UPD_FISCAL_BATCH and UPD_ACCTG_EVENT_STATUS procedure  
              04/18/2018  Vinaykumar Patil 1 Removed Reference to INFAR006_PT and INFAR001_PT tables and added P_BATCH_FILE_NAME parameter 
              09/13/2018  Vinaykumar Patil 1 Added procedures and logic for FISCAL INFAR018 related specification for row 001. 
*****************************************************************************/
c_CARS_DB           CONSTANT    INFAR006_OUTBOUND.DATA_SOURCE_CODE%TYPE         := 'CARS';

c_AE_BATCHED        CONSTANT    ACCOUNTING_ENTRY_STATUS.FS_PROCESS_STATUS%TYPE  := 'BATCHED';
c_AE_TRANSMITTED    CONSTANT    ACCOUNTING_ENTRY_STATUS.FS_PROCESS_STATUS%TYPE  := 'TRANSMITTED';
c_AE_FAILED         CONSTANT    ACCOUNTING_ENTRY_STATUS.FS_PROCESS_STATUS%TYPE  := 'FAILED';
c_AE_SELECTED       CONSTANT    ACCOUNTING_ENTRY_STATUS.FS_PROCESS_STATUS%TYPE  := 'SELECTTED';
c_NEW_STATUS        CONSTANT    ACCOUNTING_ENTRY_STATUS.FS_PROCESS_STATUS%TYPE  := 'NEW';
c_NOT_TRANSMITTED   CONSTANT    ACCOUNTING_ENTRY_STATUS.FS_PROCESS_STATUS%TYPE  := 'NOT_TRANSMITTED';

c_INFAR006_BATCH    CONSTANT    BATCH.BATCH_TYPE_CODE%TYPE                      := 'INFAR006';
c_INFAR018_BATCH    CONSTANT    BATCH.BATCH_TYPE_CODE%TYPE                      := 'INFAR018';
c_INFAR001_BATCH    CONSTANT    BATCH.BATCH_TYPE_CODE%TYPE                      := 'INFAR001';

c_BATCH_COMPLETED   CONSTANT    BATCH.STATUS%TYPE                               := 'C';
c_BATCH_TRANSMIT    CONSTANT    BATCH.STATUS%TYPE                               := 'T';
c_BATCH_ERROR       CONSTANT    BATCH.STATUS%TYPE                               := 'E';                       
c_BATCH_NOTTRANSMIT CONSTANT    BATCH.STATUS%TYPE                               := 'N';      

c_LOW_SEVERITY      CONSTANT    CARS_ERROR_LOG.SEVERITY%TYPE                    := 'LOW';
c_MEDIUM_SEVERITY   CONSTANT    CARS_ERROR_LOG.SEVERITY%TYPE                    := 'MEDIUM';
c_HIGH_SEVERITY     CONSTANT    CARS_ERROR_LOG.SEVERITY%TYPE                    := 'HIGH';

c_DELIMITER         CONSTANT    VARCHAR2(1)                                     := ',';     
c_BATCH_DATE_FORMAT CONSTANT    VARCHAR2(12)                                    := 'YYYYMMDD';
c_DATE_FORMAT       CONSTANT    VARCHAR2(12)                                    := 'MMDDRRRR';
c_DTTM_FORMAT       CONSTANT    VARCHAR2(14)                                    := 'MMDDYYYYHHMISS';
c_AMOUNT_FORMAT     CONSTANT    VARCHAR2(35)                                    := 'fm99999999999999999999990.990';

c_PU_ALL            CONSTANT    VARCHAR2(10)                                    := 'ALL';   
c_PU_CARS           CONSTANT    VARCHAR2(10)                                    := 'CARS';     
c_PU_DLSE           CONSTANT    VARCHAR2(10)                                    := 'DLSE';     
c_PU_CASH           CONSTANT    VARCHAR2(10)                                    := 'CASHIERING';     
c_PU_OSIP           CONSTANT    VARCHAR2(10)                                    := 'OSIP';     
c_PU_DWC            CONSTANT    VARCHAR2(10)                                    := 'DWC';     
    
c_BATCH_TYPE_ADJUST CONSTANT    VARCHAR2(25)                                    := 'A';     
c_BATCH_TYPE_SETUP  CONSTANT    VARCHAR2(25)                                    := 'S'; 

c_FH_ROW_ID         CONSTANT    INFAR001_OUTBOUND.FS_ROW_ID%TYPE                := '000';    
c_DC_ROW_ID         CONSTANT    INFAR001_OUTBOUND.FS_ROW_ID%TYPE                := '001';
c_PI_ROW_ID         CONSTANT    INFAR001_OUTBOUND.FS_ROW_ID%TYPE                := '002';
c_IR_ROW_ID         CONSTANT    INFAR001_OUTBOUND.FS_ROW_ID%TYPE                := '003';
c_CI_ROW_ID         CONSTANT    INFAR001_OUTBOUND.FS_ROW_ID%TYPE                := '004';
c_DJ_ROW_ID         CONSTANT    INFAR001_OUTBOUND.FS_ROW_ID%TYPE                := '005';
    
c_YES               CONSTANT    VARCHAR2(1)                                     := 'Y';
c_NO                CONSTANT    VARCHAR2(1)                                     := 'N';

c_USER              CONSTANT    BATCH.MODIFIED_BY%TYPE                          := USER;
c_SYSDATE           CONSTANT    BATCH.MODIFIED_DATE%TYPE                        := TRUNC(SYSDATE);

-- Array Table to handle data extract to file.
TYPE INFAR_REC_TYPE IS RECORD (INFAR_DATA_RECORD VARCHAR2(4000));
TYPE INFAR_DATA_TABLE IS TABLE OF INFAR_REC_TYPE;
          

    PROCEDURE LOG_CARS_ERROR(
                p_errorLevel    CARS_ERROR_LOG.ERROR_LEVEL%TYPE,
                p_severity      CARS_ERROR_LOG.SEVERITY%TYPE,
                p_errorDetail   CARS_ERROR_LOG.ERROR_DETAIL%TYPE,
                p_errorCode     CARS_ERROR_LOG.ERROR_CODE%TYPE,
                p_errorMessage  CARS_ERROR_LOG.ERROR_MESSAGE%TYPE,
                p_dataSource    CARS_ERROR_LOG.DATA_SOURCE_CODE%TYPE
                );

    FUNCTION EXTRACT_INFAR006_DATA( 
                P_SUBPROGRAM_GROUP  VARCHAR2, 
                P_TRANSACT_TYPE     VARCHAR2,
                P_BATCH_TYPE_CODE   BATCH.BATCH_TYPE_CODE%TYPE,
                P_BATCH_DATE        BATCH.CREATED_DATE%TYPE   
                ) 
                RETURN INFAR_DATA_TABLE PIPELINED;
                
    FUNCTION EXTRACT_INFAR001_DATA( 
                P_SUBPROGRAM_GROUP  VARCHAR2, 
                P_BATCH_TYPE_CODE   BATCH.BATCH_TYPE_CODE%TYPE,
                P_BATCH_DATE        BATCH.CREATED_DATE%TYPE                                    
                )  
                RETURN INFAR_DATA_TABLE PIPELINED;
                
    FUNCTION EXTRACT_INFAR018_DATA( 
                P_SUBPROGRAM_GROUP  VARCHAR2, 
                P_BATCH_TYPE_CODE   BATCH.BATCH_TYPE_CODE%TYPE,
                P_BATCH_DATE        BATCH.CREATED_DATE%TYPE                                    
                )  
                RETURN INFAR_DATA_TABLE PIPELINED;
    
    FUNCTION GET_FISCAL_BATCH_ID( 
                P_BATCH_STATUS      BATCH.STATUS%TYPE,
                P_BATCH_DATE        BATCH.CREATED_DATE%TYPE,
                P_BATCH_TYPE_CODE   BATCH.BATCH_TYPE_CODE%TYPE
               ) RETURN BATCH.BATCH_ID%TYPE;

     PROCEDURE UPD_FISCAL_DATA_STATUS (
                P_BATCH_TYPE_CODE   BATCH.BATCH_TYPE_CODE%TYPE,
                P_BATCH_DATE        BATCH.CREATED_DATE%TYPE,
                P_BATCH_STATUS      BATCH.STATUS%TYPE,
                P_BATCH_FILE_NAME   BATCH.BATCH_TYPE_CODE%TYPE
                );

END FS_DATA_FILE_PKG;
/