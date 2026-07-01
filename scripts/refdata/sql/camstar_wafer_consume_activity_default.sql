WITH ConsumeActivityLots AS (
    SELECT DISTINCT hm.ContainerId, hm.ContainerName
    FROM historymainline hm
    WHERE hm.txnDate BETWEEN DATEADD(hour, -1 * :start_hours, GETDATE())
                        AND DATEADD(hour, -1 * :end_hours, GETDATE())
      AND EXISTS (
          SELECT 1
          FROM A_ConsumeMaterialsHistory cmh
          JOIN A_ConsumeMaterialsHistoryDetai hd
            ON hd.ConsumeMaterialsHistoryID = cmh.ConsumeMaterialsHistoryID
          JOIN A_ConsumeMaterialsHistoryWafer amh
            ON amh.ConsumeMaterialsHistoryDetaiId = hd.ConsumeMaterialsHistoryDetaiId
          WHERE cmh.historyid = hm.historyid
            AND cmh.historymainlineid = hm.historymainlineid
      )
)
SELECT
    hm.ContainerName AS AssemblyLot,
    t.onsLotTypeName AS LotType,
    hm.ProductName,
    hm.historyid,
    hm.Qty AS AssemblyQty,
    CONVERT(varchar(19), hm.txnDate, 120) AS txnDate,
    am.FabLotNumber + '.S' AS FromExensioSourceLot,
    CASE
        WHEN PATINDEX('%[ -]%', amh.FromWaferScribeNumber) = 0 THEN amh.FromWaferScribeNumber
        ELSE SUBSTRING(
            SUBSTRING(amh.FromWaferScribeNumber, PATINDEX('%[^ -][^ -][^ -][^ -]%', amh.FromWaferScribeNumber), 30),
            1,
            PATINDEX('%[ -]%', SUBSTRING(amh.FromWaferScribeNumber, PATINDEX('%[^ -][^ -][^ -][^ -]%', amh.FromWaferScribeNumber), 30)) - 1
        )
        + '_' + CASE WHEN LEN(amh.FromWaferNumber) = 1 THEN '0' ELSE '' END + amh.FromWaferNumber
    END AS FromExensioWaferID,
    CASE WHEN LEN(amh.FromWaferNumber) = 1 THEN '0' ELSE '' END + amh.FromWaferNumber AS FromWaferNumber,
    CASE WHEN am.FabPlant IN ('MY2', 'ISMF') THEN 'ISMFAB' ELSE am.FabPlant END AS MaterialLotFab,
    am.FabLotNumber,
    MAX(COALESCE(am.onsSourceLotId, am.FabLotNumber)) AS MaterialLotID,
    amh.FromWaferScribeNumber,
    SUM(amh.QtyConsumed) AS QtyConsumed,
    CASE WHEN hd.QtyRequired != 0 THEN hd.QtyRequired ELSE hm.Qty * hd.ConsumeFactor END AS QtyRequired,
    hd.ConsumeFactor,
    MAX(hd.MaterialLotName) AS MaterialLotName,
    hd.MaterialPartName,
    hm.SpecName
FROM ConsumeActivityLots al
JOIN historymainline hm
  ON hm.HistoryId = al.ContainerId
 AND hm.ContainerId = al.ContainerId
LEFT JOIN A_Lotattributes a
  ON al.ContainerId = a.ContainerId
JOIN A_ConsumeMaterialsHistory h
  ON h.historyId = hm.historyid
 AND h.historymainlineid = hm.historymainlineid
JOIN A_ConsumeMaterialsHistoryDetai hd
  ON hd.ConsumeMaterialsHistoryID = h.ConsumeMaterialsHistoryID
JOIN A_ConsumeMaterialsHistoryWafer amh
  ON amh.ConsumeMaterialsHistoryDetaiId = hd.ConsumeMaterialsHistoryDetaiId
JOIN A_LotAttributes am
  ON hd.MaterialLotId = am.ContainerId
LEFT JOIN onsLotType t
  ON a.onsLotTypeId = t.onsLotTypeId
WHERE COALESCE(am.onsSourceLotId, am.FabLotNumber) IS NOT NULL
GROUP BY
    hm.ContainerName,
    t.onsLotTypeName,
    hm.ProductName,
    hm.historyid,
    hm.Qty,
    CONVERT(varchar(19), hm.txnDate, 120),
    am.FabLotNumber + '.S',
    CASE
        WHEN PATINDEX('%[ -]%', amh.FromWaferScribeNumber) = 0 THEN amh.FromWaferScribeNumber
        ELSE SUBSTRING(
            SUBSTRING(amh.FromWaferScribeNumber, PATINDEX('%[^ -][^ -][^ -][^ -]%', amh.FromWaferScribeNumber), 30),
            1,
            PATINDEX('%[ -]%', SUBSTRING(amh.FromWaferScribeNumber, PATINDEX('%[^ -][^ -][^ -][^ -]%', amh.FromWaferScribeNumber), 30)) - 1
        ) + '_' + CASE WHEN LEN(amh.FromWaferNumber) = 1 THEN '0' ELSE '' END + amh.FromWaferNumber
    END,
    CASE WHEN LEN(amh.FromWaferNumber) = 1 THEN '0' ELSE '' END + amh.FromWaferNumber,
    CASE WHEN am.FabPlant IN ('MY2', 'ISMF') THEN 'ISMFAB' ELSE am.FabPlant END,
    am.FabLotNumber,
    amh.FromWaferScribeNumber,
    CASE WHEN hd.QtyRequired != 0 THEN hd.QtyRequired ELSE hm.Qty * hd.ConsumeFactor END,
    hd.ConsumeFactor,
    hd.MaterialPartName,
    hm.SpecName
ORDER BY
    hm.ProductName,
    hm.ContainerName,
    hd.MaterialPartName,
    amh.FromWaferScribeNumber;
