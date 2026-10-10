export function stringify(value) {
  return JSON.stringify(value);
}

export function invalidOperation(sequenceNumber) {
  return JSON.stringify([
    {
      clientId: "other",
      sequenceNumber,
      minimumSequenceNumber: 0,
      clientSequenceNumber: sequenceNumber,
      referenceSequenceNumber: 0,
      type: "op",
      contents: {
        type: "groupedBatch",
        contents: [
          {
            contents: {
              type: "component",
              contents: {
                address: "missing",
                contents: {
                  type: "op",
                  content: { address: "root", contents: null },
                },
              },
            },
          },
        ],
      },
      timestamp: 0,
    },
  ]);
}
