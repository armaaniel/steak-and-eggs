import React from 'react'
import { LineChart, Line, Tooltip, ResponsiveContainer, YAxis } from 'recharts';

const StockChart = (props) => {
	return (
<div style={{width: '100%', height: '30vh'}}>
  <ResponsiveContainer width="100%" height="100%">
			<LineChart data = {props.dailyData}>
				<Line type="monotone" dataKey="close" stroke="#8884d8" strokeWidth={2} dot={false} />
      		<Tooltip cursor={false} 
			position={{ x: 0, y: 0 }}   
			labelFormatter={(index) => props.dailyData[index].date}
			/>
          <YAxis domain={[dataMin => (dataMin*0.95), dataMax => (dataMax * 1.05)]} hide={true} />
			
    		</LineChart>		
		</ResponsiveContainer>
		</div>
	)
}

export default StockChart;