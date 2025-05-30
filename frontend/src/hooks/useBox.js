import { useState, useEffect } from 'react'
import axios from 'axios'
import { API_BASE_URL } from '../config'

export function useBox(boxNumber) {
  const [box, setBox] = useState(null)
  const [hasNext, setHasNext] = useState(false)
  const [hasPrevious, setHasPrevious] = useState(false)
  const [isPending, setIsPending] = useState(true)
  const [error, setError] = useState(null)

  const fetchBox = async () => {
    setIsPending(true)
    try {
      const res = await axios.get(`${API_BASE_URL}/api/boxes/${boxNumber}`)
      setBox(res.data)
      setHasPrevious(!!res.headers['previous-box'])
      setHasNext(!!res.headers['next-box'])
      setError(null)
    } catch (err) {
      setBox(null)
      setHasPrevious(false)
      setHasNext(false)
      setError(err)
    } finally {
      setIsPending(false)
    }
  }

  const swap = async (source, target) => {
    try {
      await axios.patch(`${API_BASE_URL}/api/boxes`, { swap: { source, target } })

      if (source.boxNumber === boxNumber || target.boxNumber === boxNumber) {
        fetchBox()
      }
    } catch (err) {
      setError(err)
    }
  }

  useEffect(() => {
    fetchBox()
  }, [boxNumber])

  return { box, hasNext, hasPrevious, isPending, error, swap }
}

export default useBox