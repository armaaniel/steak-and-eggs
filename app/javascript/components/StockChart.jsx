import React, { useState, useEffect } from 'react'
import { LineChart, Line, Tooltip, ResponsiveContainer, YAxis } from 'recharts';

const StockChart = (props) => {
	
	const [chartData, setChartData] = useState([])
	
	useEffect(() => {
		async function getData() {
			try {
				const response = await fetch (`/stocks/${props.symbol}/chartdata`)
				const data = await response.json()
				
				setChartData(data)
				console.log(data)
			} catch (error) {
				console.error(error)
			}
		} getData()
	}, [props.symbol])
	
	if (chartData.length === 0) { 
  	  return <div className='skeleton-chart'></div>;
	}
	
	return (
	
	<div className='chart'>
	<ResponsiveContainer width="100%" height="100%">
	
		<LineChart data = {chartData}>
		<Line type="monotone" dataKey="close" stroke="#8884d8" strokeWidth={2} dot={false} />
		
      	<Tooltip cursor={false} position={{ x: 0, y: 0 }} labelFormatter={(index) => chartData[index].date}
		contentStyle={{ border: 'none', background: 'none', display: 'flex', padding:'4px', gap:'8px' }}/>
		
        <YAxis domain={[dataMin => (dataMin*0.95), dataMax => (dataMax * 1.05)]} hide={true} />
		</LineChart>		
		
	</ResponsiveContainer>
	</div>
	)
}

export default StockChart;