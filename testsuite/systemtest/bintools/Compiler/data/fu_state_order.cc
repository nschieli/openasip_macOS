/**
 * Behaviour of a stateful test operation set: every instance of the
 * function unit has a state of its own (eight entries and a checksum).
 */

#include "OSAL.hh"

DEFINE_STATE(ACC_STATE)
    unsigned int entry[8];
    unsigned int sum;

INIT_STATE(ACC_STATE)
    for (int i = 0; i < 8; ++i) entry[i] = 0;
    sum = 0;
END_INIT_STATE;

FINALIZE_STATE(ACC_STATE)
END_FINALIZE_STATE;

END_DEFINE_STATE

OPERATION_WITH_STATE(ACCWR, ACC_STATE)
TRIGGER
    STATE.entry[UINT(1) & 7] = UINT(2);
    RETURN_READY;
END_TRIGGER;
END_OPERATION_WITH_STATE(ACCWR)

OPERATION_WITH_STATE(ACCSUM, ACC_STATE)
TRIGGER
    unsigned int n = UINT(1) > 8 ? 8 : UINT(1);
    unsigned int s = 0;
    for (unsigned int i = 0; i < n; ++i) {
        s = (s << 5 | s >> 27) ^ STATE.entry[i];
    }
    STATE.sum = s;
    RETURN_READY;
END_TRIGGER;
END_OPERATION_WITH_STATE(ACCSUM)

OPERATION_WITH_STATE(ACCRD, ACC_STATE)
TRIGGER
    IO(2) = STATE.sum;
    RETURN_READY;
END_TRIGGER;
END_OPERATION_WITH_STATE(ACCRD)
